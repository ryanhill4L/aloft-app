// The commands Aloft is willing to form. Numbers and bodies from NOOP's
// Strand/BLE/Commands.swift, docs/PROTOCOL_ALARMS.md, and
// WhoopProtocol/Resources/whoop_protocol.json (ryanbr/noop@2a1de760).
//
// FORCE_TRIM (25), SET_READ_POINTER (33), firmware load, DFU, and fuel-gauge
// reset are deliberately absent: an ack that advances the trim lets the strap
// delete history the phone does not have.
//
// Commands 19 and 79 are not cases here. They share a number with a different
// operation on the other generation, so each lives on that generation's encoder
// only (`StrapCommand.Whoop5.buzz`, `StrapCommand.Whoop4.runHapticsPattern`).
public enum StrapCommand: UInt8, Sendable, CaseIterable {
    case setClock = 10
    case getClock = 11
    case abortHistoricalTransmits = 20
    case sendHistoricalData = 22
    case historicalDataResult = 23
    case getBatteryLevel = 26
    case getDataRange = 34
    case getHelloHarvard = 35
    case sendR10R11Realtime = 63
    case setAlarmTime = 66
    case getAlarmTime = 67
    case runAlarm = 68
    case disableAlarm = 69
    case stopHaptics = 122
    case getHello = 145

    /// WHOOP 4 only. 5/MG rejects 79 with result 3 and buzzes with command 19.
    public enum Whoop4: UInt8, Sendable {
        case runHapticsPattern = 79
    }

    /// 5/MG only. On a WHOOP 4 this number is SET_R7_REALTIME_STREAM.
    public enum Whoop5: UInt8, Sendable {
        case buzz = 19
    }
}

/// The GATT layout per family, as strings so this package stays free of
/// CoreBluetooth. The app turns these into `CBUUID`s.
public struct StrapGATT: Sendable {
    public let service: String
    public let commandWrite: String
    public let notify: [String]

    public static let whoop4 = StrapGATT(
        service: "61080001-8D6D-82B8-614A-1C8CB0F8DCC6",
        commandWrite: "61080002-8D6D-82B8-614A-1C8CB0F8DCC6",
        notify: ["61080003-8D6D-82B8-614A-1C8CB0F8DCC6", "61080004-8D6D-82B8-614A-1C8CB0F8DCC6", "61080005-8D6D-82B8-614A-1C8CB0F8DCC6"]
    )

    public static let whoop5 = StrapGATT(
        service: "FD4B0001-CCE1-4033-93CE-002D5875F58A",
        commandWrite: "FD4B0002-CCE1-4033-93CE-002D5875F58A",
        notify: ["FD4B0003-CCE1-4033-93CE-002D5875F58A", "FD4B0004-CCE1-4033-93CE-002D5875F58A", "FD4B0005-CCE1-4033-93CE-002D5875F58A", "FD4B0007-CCE1-4033-93CE-002D5875F58A"]
    )

    public static let heartRateService = "180D"
    public static let heartRateMeasurement = "2A37"
    public static let batteryService = "180F"
    public static let batteryLevel = "2A19"

    public static func forFamily(_ family: StrapFamily) -> StrapGATT { family == .whoop4 ? .whoop4 : .whoop5 }
}

/// One strap generation. `CommandEncoder` is generic over this, so a command
/// that exists on only one generation cannot be named on the other.
public protocol StrapGeneration {
    static var family: StrapFamily { get }
}

public enum Whoop4Generation: StrapGeneration {
    public static var family: StrapFamily { .whoop4 }
}

/// Ryan's strap is a WHOOP 5.0/MG. Alarm and haptic builders on this generation
/// are the ones to send.
public enum Whoop5Generation: StrapGeneration {
    public static var family: StrapFamily { .whoop5 }

    /// One of the six alarm slots. 0 and 255 are not slots; 255 means every slot
    /// on DISABLE only, and that body is `disableAllAlarms`, not a slot.
    public struct AlarmSlot: RawRepresentable, Sendable, Equatable, Hashable {
        public let rawValue: UInt8

        public init?(rawValue: UInt8) {
            guard (1...6).contains(rawValue) else { return nil }
            self.rawValue = rawValue
        }
    }
}

/// Builds outgoing frames with one wrapping sequence counter per connection.
public struct CommandEncoder<G: StrapGeneration>: Sendable {
    public static var family: StrapFamily { G.family }
    private var sequence: UInt8 = 0

    public init() {}

    public mutating func frame(_ command: StrapCommand, body: [UInt8] = [0x00]) -> [UInt8] {
        sequence &+= 1
        return Frame.command(G.family, sequence: sequence, command: command.rawValue, body: body)
    }

    /// Starts a history offload. Send `.withResponse`.
    public mutating func startHistory() -> [UInt8] { frame(.sendHistoricalData) }

    /// Acks one chunk: `01` plus the END frame's 8-byte block, verbatim.
    /// Only call after the chunk's rows are durable.
    public mutating func ackHistory(endData: [UInt8]) -> [UInt8] {
        precondition(endData.count == 8)
        return frame(.historicalDataResult, body: [0x01] + endData)
    }
}

extension CommandEncoder where G == Whoop5Generation {
    /// GET_HELLO, seq 1, body `01`. Write it `.withResponse` before subscribing
    /// the fd4b notify characteristics. That confirmed write is what asks iOS
    /// to start a just-works bond. The bytes are a command, not a key exchange.
    /// Subscribing fd4b0003/4/5/7 first is refused and wedges the bond
    /// (noop BLEManager didDiscoverCharacteristics, issue #17).
    public static let clientHello: [UInt8] = [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71, 0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D]

    /// An un-clocked 5/MG does not bank data to flash.
    public mutating func connectSequence(unixSeconds: UInt32) -> [[UInt8]] {
        let clock8 = le32(unixSeconds) + [0, 0, 0, 0]
        return [frame(.setClock, body: clock8), frame(.getClock, body: [])]
    }

    /// Fractional ticks of a second at the strap clock's 1/32768 resolution.
    /// `123` ms is `4030` ticks, the value in NOOP's 5/MG alarm golden.
    public static func fractionTicks(millisecond: Int) -> UInt16 {
        let ms = UInt32(min(max(millisecond, 0), 999))
        return UInt16((ms * 32_768) / 1_000)
    }

    /// SET_ALARM_TIME rev 4. 21 bytes. The strap stores one slot and clears it
    /// when the alarm fires, so the app re-arms on the next connect.
    public static func setAlarmBody(slot: Whoop5Generation.AlarmSlot, unixSeconds: UInt32, fractionTicks: UInt16) -> [UInt8] {
        [0x04, slot.rawValue]
            + le32(unixSeconds)
            + [UInt8(fractionTicks & 0xFF), UInt8(fractionTicks >> 8)]
            + [0x2F, 0x98, 0, 0, 0, 0, 0, 0]
            + [0, 0, 7, 30, 0]
    }

    /// GET_ALARM_TIME. The reply is the same 21-byte record.
    public static func getAlarmBody(slot: Whoop5Generation.AlarmSlot) -> [UInt8] {
        [0x04, slot.rawValue]
    }

    /// RUN_ALARM, revision 2 plus the slot.
    public static func runAlarmBody(slot: Whoop5Generation.AlarmSlot) -> [UInt8] {
        [0x02, slot.rawValue]
    }

    /// DISABLE_ALARM for one slot.
    public static func disableAlarmBody(slot: Whoop5Generation.AlarmSlot) -> [UInt8] {
        [0x02, slot.rawValue]
    }

    /// DISABLE_ALARM for all six slots (`02 FF`).
    public static func disableAllAlarmsBody() -> [UInt8] { [0x02, 0xFF] }

    /// Command 19 buzz. `repeats` is how many pulses; the wire byte is
    /// `repeats - 1`, clamped to 0...7. One pulse is the captured body
    /// `01 2F 98` then nine zeros.
    public static func buzzBody(repeats: UInt8) -> [UInt8] {
        let afterFirst: UInt8 = repeats == 0 ? 0 : min(repeats, 8) - 1
        return [0x01, 0x2F, 0x98, 0, 0, 0, 0, 0, 0, 0, 0, afterFirst]
    }

    /// STOP_HAPTICS. Revision 1.
    public static func stopHapticsBody() -> [UInt8] { [0x01] }

    public mutating func setAlarm(slot: Whoop5Generation.AlarmSlot, unixSeconds: UInt32, fractionTicks: UInt16 = 0) -> [UInt8] {
        frame(.setAlarmTime, body: Self.setAlarmBody(slot: slot, unixSeconds: unixSeconds, fractionTicks: fractionTicks))
    }

    public mutating func getAlarm(slot: Whoop5Generation.AlarmSlot) -> [UInt8] {
        frame(.getAlarmTime, body: Self.getAlarmBody(slot: slot))
    }

    public mutating func runAlarm(slot: Whoop5Generation.AlarmSlot) -> [UInt8] {
        frame(.runAlarm, body: Self.runAlarmBody(slot: slot))
    }

    public mutating func disableAlarm(slot: Whoop5Generation.AlarmSlot) -> [UInt8] {
        frame(.disableAlarm, body: Self.disableAlarmBody(slot: slot))
    }

    public mutating func disableAllAlarms() -> [UInt8] {
        frame(.disableAlarm, body: Self.disableAllAlarmsBody())
    }

    public mutating func buzz(repeats: UInt8 = 1) -> [UInt8] {
        frame(.buzz, body: Self.buzzBody(repeats: repeats))
    }

    public mutating func stopHaptics() -> [UInt8] {
        frame(.stopHaptics, body: Self.stopHapticsBody())
    }

    private mutating func frame(_ command: StrapCommand.Whoop5, body: [UInt8]) -> [UInt8] {
        sequence &+= 1
        return Frame.command(G.family, sequence: sequence, command: command.rawValue, body: body)
    }
}

extension CommandEncoder where G == Whoop4Generation {
    /// WHOOP 4 firmware differs on which clock form it latches, so both go out.
    public mutating func connectSequence(unixSeconds: UInt32) -> [[UInt8]] {
        let clock8 = le32(unixSeconds) + [0, 0, 0, 0]
        return [
            frame(.getHelloHarvard),
            frame(.setClock, body: le32(unixSeconds) + [0, 0, 0, 0, 0]),
            frame(.setClock, body: clock8),
            frame(.getClock, body: []),
            frame(.getClock),
            frame(.sendR10R11Realtime, body: [0x00]),
            frame(.getDataRange),
        ]
    }

    /// SET_ALARM_TIME. Nine bytes: form `01`, epoch, then four zeros. The
    /// seven-byte form was acknowledged and did not buzz.
    public static func setAlarmBody(unixSeconds: UInt32) -> [UInt8] {
        [0x01] + le32(unixSeconds) + [0, 0, 0, 0]
    }

    public static func getAlarmBody() -> [UInt8] { [0x01] }
    public static func runAlarmBody() -> [UInt8] { [0x01] }
    public static func disableAlarmBody() -> [UInt8] { [0x01] }

    /// RUN_HAPTICS_PATTERN. Preset 2, three loops.
    public static func runHapticsBody() -> [UInt8] { [0x02, 0x03, 0x00, 0x00, 0x00] }

    /// STOP_HAPTICS.
    public static func stopHapticsBody() -> [UInt8] { [0x00] }

    public mutating func setAlarm(unixSeconds: UInt32) -> [UInt8] {
        frame(.setAlarmTime, body: Self.setAlarmBody(unixSeconds: unixSeconds))
    }

    public mutating func getAlarm() -> [UInt8] { frame(.getAlarmTime, body: Self.getAlarmBody()) }
    public mutating func runAlarm() -> [UInt8] { frame(.runAlarm, body: Self.runAlarmBody()) }
    public mutating func disableAlarm() -> [UInt8] { frame(.disableAlarm, body: Self.disableAlarmBody()) }
    public mutating func stopHaptics() -> [UInt8] { frame(.stopHaptics, body: Self.stopHapticsBody()) }

    public mutating func runHaptics() -> [UInt8] {
        frame(.runHapticsPattern, body: Self.runHapticsBody())
    }

    private mutating func frame(_ command: StrapCommand.Whoop4, body: [UInt8]) -> [UInt8] {
        sequence &+= 1
        return Frame.command(G.family, sequence: sequence, command: command.rawValue, body: body)
    }
}
