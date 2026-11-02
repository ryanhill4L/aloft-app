/// The standard Bluetooth Heart Rate Measurement (0x2A37).
public struct HeartRateMeasurement: Sendable, Equatable {
    public enum Contact: Sendable, Equatable { case unsupported, notDetected, detected }

    public var bpm: Int
    public var contact: Contact
    public var rrMilliseconds: [Int]

    /// R-R units: the spec says 1/1024 s, and WHOOP 4 follows it. WHOOP 5/MG
    /// firmware sends milliseconds (NOOP measured this on 50.41.1.0).
    public init?(_ data: [UInt8], family: StrapFamily) {
        guard let flags = data.first else { return nil }
        var i = 1
        if flags & 0x01 != 0 {
            guard data.count >= 3 else { return nil }
            bpm = Int(data.u16(at: 1))
            i = 3
        } else {
            guard data.count >= 2 else { return nil }
            bpm = Int(data[1])
            i = 2
        }
        switch flags & 0x06 {
        case 0x06: contact = .detected
        case 0x04: contact = .notDetected
        default: contact = .unsupported
        }
        if flags & 0x08 != 0 { i += 2 }
        rrMilliseconds = []
        if flags & 0x10 != 0 {
            while i + 1 < data.count {
                let raw = Int(data.u16(at: i))
                rrMilliseconds.append(family == .whoop4 ? Int((Double(raw) * 1000 / 1024).rounded()) : raw)
                i += 2
            }
        }
    }
}
