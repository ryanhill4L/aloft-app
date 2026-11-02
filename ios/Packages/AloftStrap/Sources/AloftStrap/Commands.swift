// The commands Aloft is willing to form. Numbers and bodies from NOOP's
// Strand/BLE/Commands.swift and BLEManager (ryanbr/noop@2a1de760).
//
// FORCE_TRIM (25), SET_READ_POINTER (33), firmware load, DFU, and fuel-gauge
// reset are deliberately absent: an ack that advances the trim lets the strap
// delete history the phone does not have.
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
    case getHello = 145
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

/// Builds outgoing frames with one wrapping sequence counter per connection.
public struct CommandEncoder: Sendable {
    public let family: StrapFamily
    private var sequence: UInt8 = 0

    public init(family: StrapFamily) { self.family = family }

    /// 5/MG: written once after subscribing, `.withResponse`; it triggers the
    /// just-works bond. GET_HELLO, seq 1, body `01`.
    public static let whoop5ClientHello: [UInt8] = [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71, 0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D]

    public mutating func frame(_ command: StrapCommand, body: [UInt8] = [0x00]) -> [UInt8] {
        sequence &+= 1
        return Frame.command(family, sequence: sequence, command: command.rawValue, body: body)
    }

    /// The frames sent once per connection, after the bond write succeeds.
    /// WHOOP 4 firmware differs on which clock form it latches, so both go out.
    public mutating func connectSequence(unixSeconds: UInt32) -> [[UInt8]] {
        let clock8 = le32(unixSeconds) + [0, 0, 0, 0]
        switch family {
        case .whoop4:
            return [
                frame(.getHelloHarvard),
                frame(.setClock, body: le32(unixSeconds) + [0, 0, 0, 0, 0]),
                frame(.setClock, body: clock8),
                frame(.getClock, body: []),
                frame(.getClock),
                frame(.sendR10R11Realtime, body: [0x00]),
                frame(.getDataRange),
            ]
        case .whoop5:
            // An un-clocked 5/MG does not bank data to flash.
            return [frame(.setClock, body: clock8), frame(.getClock, body: [])]
        }
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
