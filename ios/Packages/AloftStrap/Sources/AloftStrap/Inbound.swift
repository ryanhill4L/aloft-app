// Command responses (type 36) and strap events (type 48).
// Field positions are WHOOP 4 offsets from whoop_protocol.json EVENT and from
// FrameRouter.commandResultByte (ryanbr/noop@2a1de760). `Frame.offset` adds
// four on 5/MG, so the response window is bytes 10...13 there and 6...9 on a
// WHOOP 4. Ryan's strap is a 5/MG: read that window.

/// A type-36 reply. The four-byte window is command, the request's sequence,
/// the result code, then the first body byte.
///
/// Result codes NOOP records: 0 failure, 1 success (not proof the motor ran),
/// 2 pending, 3 unsupported. Any other value stays the raw number.
public struct CommandResponse: Sendable, Equatable {
    public let command: UInt8
    public let originSequence: UInt8
    public let result: UInt8
    public let body: [UInt8]

    public init(command: UInt8, originSequence: UInt8, result: UInt8, body: [UInt8]) {
        self.command = command
        self.originSequence = originSequence
        self.result = result
        self.body = body
    }

    public var resultName: String {
        switch result {
        case 0: "failure"
        case 1: "success"
        case 2: "pending"
        case 3: "unsupported"
        default: "result \(result)"
        }
    }
}

/// A type-48 event. `id` is the raw event number. Known ids also have a name.
public struct StrapEvent: Sendable, Equatable {
    public let id: UInt8
    /// Strap unix seconds. The schema's event timestamp is a u32.
    public let unixSeconds: UInt32

    public init(id: UInt8, unixSeconds: UInt32) {
        self.id = id
        self.unixSeconds = unixSeconds
    }

    public enum Name: String, Sendable, Equatable {
        case wristOn = "wrist on"
        case wristOff = "wrist off"
        case doubleTap = "double tap"
        case alarmSet = "alarm set"
        case alarmFired = "alarm fired"
        case alarmFiredByApp = "alarm fired by app"
        case hapticsFired = "haptics fired"
    }

    /// 60 is HAPTICS_FIRED and 100 is HAPTICS_TERMINATED in the schema. Both
    /// are haptics fired here; the raw `id` still tells them apart.
    public var name: Name? {
        switch id {
        case 9: .wristOn
        case 10: .wristOff
        case 14: .doubleTap
        case 56: .alarmSet
        case 57: .alarmFired
        case 58: .alarmFiredByApp
        case 60, 100: .hapticsFired
        default: nil
        }
    }

    public var label: String { name?.rawValue ?? "event \(id)" }
}

extension Frame {
    /// Type 36. Nil when the frame is not a response or is too short to hold
    /// the result byte. The body runs up to the CRC-32 trailer and keeps any
    /// 5/MG padding zeros.
    public var commandResponse: CommandResponse? {
        guard type == .commandResponse else { return nil }
        let bodyAt = offset(9)
        let trailer = bytes.count - 4
        guard offset(8) < trailer, bodyAt <= trailer else { return nil }
        return CommandResponse(
            command: bytes[offset(6)],
            originSequence: bytes[offset(7)],
            result: bytes[offset(8)],
            body: Array(bytes[bodyAt..<trailer])
        )
    }

    /// Type 48. Event id is at WHOOP 4 offset 6, timestamp at offset 8.
    public var strapEvent: StrapEvent? {
        guard type == .event else { return nil }
        let tsAt = offset(8)
        guard tsAt + 4 <= bytes.count - 4 else { return nil }
        return StrapEvent(id: bytes[offset(6)], unixSeconds: bytes.u32(at: tsAt))
    }
}
