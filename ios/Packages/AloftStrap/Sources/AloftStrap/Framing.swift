// Strap framing, rewritten from NOOP's Framing.swift
// (ryanbr/noop@2a1de760, Packages/WhoopProtocol). Facts only: CRC parameters,
// header layouts, and the resync rule.

/// WHOOP 4 and WHOOP 5/MG do not share a frame layout. Never shift offsets
/// from one onto the other.
public enum StrapFamily: Sendable, Equatable {
    case whoop4
    case whoop5

    /// Bytes before the inner record (type, seq, cmd, body).
    var headerLength: Int { self == .whoop4 ? 4 : 8 }
    var minimumFrame: Int { self == .whoop4 ? 11 : 13 }
    static let maximumFrame = 8192

    /// Total frame size implied by the header, or nil if not enough bytes.
    func declaredTotal(_ bytes: ArraySlice<UInt8>) -> Int? {
        let base = bytes.startIndex
        switch self {
        case .whoop4:
            guard bytes.count >= 3 else { return nil }
            return (Int(bytes[base + 1]) | Int(bytes[base + 2]) << 8) + 4
        case .whoop5:
            guard bytes.count >= 4 else { return nil }
            return (Int(bytes[base + 2]) | Int(bytes[base + 3]) << 8) + 8
        }
    }

    func headerValid(_ bytes: ArraySlice<UInt8>) -> Bool {
        let b = Array(bytes.prefix(headerLength))
        guard b.count == headerLength else { return false }
        switch self {
        case .whoop4:
            return CRC.crc8(b[1...2]) == b[3]
        case .whoop5:
            return CRC.crc16(b[0...5]) == UInt16(b[6]) | UInt16(b[7]) << 8
        }
    }
}

public enum CRC {
    /// CRC-8/SMBUS: poly 0x07, init 0, not reflected.
    public static func crc8<C: Collection>(_ data: C) -> UInt8 where C.Element == UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            crc ^= byte
            for _ in 0..<8 {
                crc = crc & 0x80 != 0 ? (crc << 1) ^ 0x07 : crc << 1
            }
        }
        return crc
    }

    /// CRC-16/MODBUS: reflected poly 0xA001, init 0xFFFF.
    public static func crc16<C: Collection>(_ data: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    /// zlib CRC-32: reflected poly 0xEDB88320, init and xorout 0xFFFFFFFF.
    public static func crc32<C: Collection>(_ data: C) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

public enum PacketType: UInt8, Sendable {
    case command = 35
    case commandResponse = 36
    case realtimeData = 40
    case realtimeRawData = 43
    case historicalData = 47
    case event = 48
    case metadata = 49
    case consoleLogs = 50

    /// 5/MG aliases: 38 is a command response and 56 is metadata.
    init?(wire: UInt8) {
        switch wire {
        case 38: self = .commandResponse
        case 56: self = .metadata
        default: self.init(rawValue: wire)
        }
    }
}

public enum FrameError: Error, Equatable {
    case noStartByte, tooShort, lengthMismatch, headerCRC, payloadCRC
}

/// A complete frame whose CRCs have been checked.
public struct Frame: Sendable, Equatable {
    public let family: StrapFamily
    public let bytes: [UInt8]

    public init(family: StrapFamily, bytes: [UInt8]) throws {
        guard bytes.first == 0xAA else { throw FrameError.noStartByte }
        guard bytes.count >= family.minimumFrame else { throw FrameError.tooShort }
        guard family.declaredTotal(bytes[...]) == bytes.count else { throw FrameError.lengthMismatch }
        guard family.headerValid(bytes[...]) else { throw FrameError.headerCRC }
        let inner = bytes[family.headerLength..<(bytes.count - 4)]
        guard CRC.crc32(inner) == bytes.u32(at: bytes.count - 4) else { throw FrameError.payloadCRC }
        self.family = family
        self.bytes = bytes
    }

    var base: Int { family.headerLength }
    public var rawType: UInt8 { bytes[base] }
    public var type: PacketType? { PacketType(wire: rawType) }
    /// The sequence byte; for historical records it is the layout version.
    public var sequence: UInt8 { bytes[base + 1] }
    public var command: UInt8 { bytes[base + 2] }

    /// Absolute offset into `bytes` for a WHOOP 4 offset. 5/MG fields sit
    /// four bytes later.
    func offset(_ whoop4Offset: Int) -> Int { whoop4Offset + (family == .whoop5 ? 4 : 0) }

    /// Builds a type-35 command frame.
    public static func command(_ family: StrapFamily, sequence: UInt8, command: UInt8, body: [UInt8]) -> [UInt8] {
        encode(family, type: PacketType.command.rawValue, sequence: sequence, command: command, body: body)
    }

    static func encode(_ family: StrapFamily, type: UInt8, sequence: UInt8, command: UInt8, body: [UInt8]) -> [UInt8] {
        var inner = [type, sequence, command] + body
        switch family {
        case .whoop4:
            let length = UInt16(inner.count + 4)
            let lengthBytes = [UInt8(length & 0xFF), UInt8(length >> 8)]
            return [0xAA] + lengthBytes + [CRC.crc8(lengthBytes)] + inner + le32(CRC.crc32(inner))
        case .whoop5:
            while inner.count % 4 != 0 { inner.append(0) }
            let declared = UInt16(inner.count + 4)
            let header: [UInt8] = [0xAA, 0x01, UInt8(declared & 0xFF), UInt8(declared >> 8), 0x00, 0x01]
            let headerCRC = CRC.crc16(header)
            return header + [UInt8(headerCRC & 0xFF), UInt8(headerCRC >> 8)] + inner + le32(CRC.crc32(inner))
        }
    }
}

/// Rebuilds frames from notification fragments. One per connection; feed every
/// notify characteristic in arrival order. Payload CRCs are checked by `Frame`.
public struct Reassembler: Sendable {
    public let family: StrapFamily
    private var buffer: [UInt8] = []
    public private(set) var droppedHeaders = 0

    public init(family: StrapFamily) { self.family = family }

    public mutating func append(_ fragment: [UInt8]) -> [[UInt8]] {
        buffer += fragment
        var frames: [[UInt8]] = []
        while true {
            guard let start = buffer.firstIndex(of: 0xAA) else {
                buffer.removeAll()
                break
            }
            buffer.removeFirst(start)
            guard let total = family.declaredTotal(buffer[...]) else { break }
            if total < family.minimumFrame || total > StrapFamily.maximumFrame {
                droppedHeaders += 1
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= family.headerLength else { break }
            // A stray 0xAA inside a payload fails its header CRC; resync past it.
            guard family.headerValid(buffer[...]) else {
                droppedHeaders += 1
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= total else { break }
            frames.append(Array(buffer[..<total]))
            buffer.removeFirst(total)
        }
        return frames
    }
}

func le32(_ v: UInt32) -> [UInt8] {
    [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
}

extension Array where Element == UInt8 {
    func u16(at i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func u32(at i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}

extension Array where Element == UInt8 {
    public init?(hex: String) {
        let chars = [Character](hex.filter { !$0.isWhitespace })
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String([chars[i], chars[i + 1]]), radix: 16) else { return nil }
            out.append(byte)
        }
        self = out
    }
}
