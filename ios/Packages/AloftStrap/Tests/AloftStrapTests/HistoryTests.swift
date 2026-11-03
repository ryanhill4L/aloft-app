import Foundation
import Testing
@testable import AloftStrap

@Suite struct HistoryTests {
    static let now: Int64 = 1_800_000_000

    // HISTORY_END frames from NOOP's public tests.
    static let w4End = [UInt8](hex: "aa15001631000200f1536500000000000039300000c3401bdb")!
    static let w5End = [UInt8](hex: "aa011c00010023d1316a0284a3266a0a373d00000041b601001000000000000044d21e3d")!

    /// A synthetic v24 WHOOP 4 record: unix at 11, HR at 21, R-R at 22/23.
    static func w4Record(unix: UInt32, hr: UInt8, rr: [UInt16]) -> [UInt8] {
        var body = [UInt8](repeating: 0, count: 24) // frame offsets 7..<31
        body.replaceSubrange(4..<8, with: le32(unix))
        body[14] = hr
        body[15] = UInt8(rr.count)
        for (i, v) in rr.enumerated() {
            body[16 + 2 * i] = UInt8(v & 0xFF)
            body[17 + 2 * i] = UInt8(v >> 8)
        }
        return Frame.encode(.whoop4, type: 47, sequence: 24, command: 0, body: body)
    }

    /// A synthetic v18 WHOOP 5 record: unix at 15, HR at 22, R-R at 23/24.
    static func w5Record(unix: UInt32, hr: UInt8, rr: [UInt16]) -> [UInt8] {
        var body = [UInt8](repeating: 0, count: 48) // frame offsets 11...
        body.replaceSubrange(4..<8, with: le32(unix))
        body[11] = hr
        body[12] = UInt8(rr.count)
        for (i, v) in rr.enumerated() {
            body[13 + 2 * i] = UInt8(v & 0xFF)
            body[14 + 2 * i] = UInt8(v >> 8)
        }
        return Frame.encode(.whoop5, type: 47, sequence: 18, command: 0, body: body)
    }

    @Test func endMarkersKeepTheirBlockVerbatim() throws {
        let w4 = try Frame(family: .whoop4, bytes: Self.w4End)
        // On WHOOP 4 the block runs into the frame's own CRC-32 trailer.
        #expect(w4.historyMarker == .end(trim: 12345, endData: [0x39, 0x30, 0x00, 0x00, 0xC3, 0x40, 0x1B, 0xDB]))
        let w5 = try Frame(family: .whoop5, bytes: Self.w5End)
        #expect(w5.historyMarker == .end(trim: 112_193, endData: [0x41, 0xB6, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00]))
    }

    @Test func decodesRecordsOnBothFamilies() throws {
        let w4 = try Frame(family: .whoop4, bytes: Self.w4Record(unix: 1_780_000_000, hr: 58, rr: [1012, 0, 998]))
        #expect(w4.historicalSamples() == SampleBatch(
            heartRate: [HeartRateSample(timestampMs: 1_780_000_000_000, bpm: 58)],
            rr: [RRInterval(timestampMs: 1_780_000_000_000, milliseconds: 1012), RRInterval(timestampMs: 1_780_000_000_000, milliseconds: 998)]
        ))
        let w5 = try Frame(family: .whoop5, bytes: Self.w5Record(unix: 1_780_916_150, hr: 102, rr: [602, 613]))
        #expect(w5.historicalSamples().heartRate == [HeartRateSample(timestampMs: 1_780_916_150_000, bpm: 102)])
        #expect(w5.historicalSamples().rr.map(\.milliseconds) == [602, 613])
    }

    @Test func implausibleTimestampsAreDropped() throws {
        var session = HistorySession()
        _ = session.receive(try Frame(family: .whoop4, bytes: Self.w4Record(unix: 1_000, hr: 60, rr: [])), now: Self.now)
        _ = session.receive(try Frame(family: .whoop4, bytes: Self.w4Record(unix: 1_780_000_000, hr: 61, rr: [])), now: Self.now)
        guard case let .persist(batch, _, _) = session.receive(try Frame(family: .whoop4, bytes: Self.w4End), now: Self.now) else {
            Issue.record("expected persist")
            return
        }
        #expect(batch.heartRate.map(\.bpm) == [61])
    }

    @Test func ackOnlyAfterDurableInsert() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "aloft-sync-\(UUID().uuidString)/\(StrapStore.fileName)")
        let store = try StrapStore(url: url)
        let sync = HistorySync(family: .whoop5, store: store)

        let record = try Frame(family: .whoop5, bytes: Self.w5Record(unix: 1_780_916_150, hr: 102, rr: [602]))
        #expect(await sync.receive(record, now: Self.now).0 == .collected)

        let (outcome, ack) = await sync.receive(try Frame(family: .whoop5, bytes: Self.w5End), now: Self.now)
        #expect(outcome == .ack(rowsWritten: 2, trim: 112_193))
        let ackFrame = try Frame(family: .whoop5, bytes: try #require(ack))
        #expect(ackFrame.command == StrapCommand.historicalDataResult.rawValue)
        #expect(Array(ackFrame.bytes[11..<20]) == [0x01, 0x41, 0xB6, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00])
        #expect(try await store.counts().heartRate == 1)
    }

    @Test func aFailedWriteStallsEveryLaterAck() async throws {
        var session = HistorySession()
        session.markFailed()
        // HistorySync refuses to ack once stalled, even for an empty chunk.
        let step = session.receive(try Frame(family: .whoop5, bytes: Self.w5End), now: Self.now)
        guard case .persist = step else {
            Issue.record("END still yields a persist step")
            return
        }
        #expect(session.stalled)
    }

    @Test func eventFramesAreNotHistory() async throws {
        var session = HistorySession()
        let event = try Frame(family: .whoop5, bytes: Frame.encode(
            .whoop5, type: 48, sequence: 1, command: 57, body: [0x00] + le32(1_780_916_150)
        ))
        #expect(session.receive(event, now: Self.now) == .ignored)
        _ = session.receive(try Frame(family: .whoop5, bytes: Self.w5Record(unix: 1_780_916_150, hr: 102, rr: [602])), now: Self.now)
        #expect(session.receive(event, now: Self.now) == .ignored)
        guard case let .persist(batch, _, _) = session.receive(try Frame(family: .whoop5, bytes: Self.w5End), now: Self.now) else {
            Issue.record("expected persist")
            return
        }
        #expect(batch.heartRate.map(\.bpm) == [102])

        let url = FileManager.default.temporaryDirectory.appending(path: "aloft-event-sync-\(UUID().uuidString)/\(StrapStore.fileName)")
        let sync = HistorySync(family: .whoop5, store: try StrapStore(url: url))
        let (outcome, ack) = await sync.receive(event, now: Self.now)
        #expect(outcome == .ignored)
        #expect(ack == nil)
    }

    @Test func standardHeartRate() {
        let w4 = HeartRateMeasurement([0x16, 72, 0x00, 0x04], family: .whoop4)
        #expect(w4 == HeartRateMeasurement.init([0x16, 72, 0x00, 0x04], family: .whoop4))
        #expect(w4?.bpm == 72)
        #expect(w4?.contact == .detected)
        #expect(w4?.rrMilliseconds == [1000])
        #expect(HeartRateMeasurement([0x16, 72, 0x00, 0x04], family: .whoop5)?.rrMilliseconds == [1024])
        #expect(HeartRateMeasurement([0x04, 60], family: .whoop5)?.contact == .notDetected)
        #expect(HeartRateMeasurement([0x01, 0x2C, 0x01], family: .whoop5)?.bpm == 300)
        #expect(HeartRateMeasurement([], family: .whoop5) == nil)
    }
}
