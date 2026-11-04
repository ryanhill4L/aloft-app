import Foundation
import Testing
@testable import AloftStrap

/// The milestone 1 durability proof from AGENTS.md: rows must be in the main
/// file, not only in `-wal`, by the time `insert` returns.
@Suite struct StrapStoreDurabilityTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "aloft-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func mainFileOnlyCopy(of url: URL) throws -> URL {
        let copyDir = dir.appending(path: "copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: copyDir, withIntermediateDirectories: true)
        let copy = copyDir.appending(path: StrapStore.fileName)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    private func heartRateRows(in url: URL) throws -> Int {
        let db = try SQLiteConnection(path: url.path)
        let stmt = try db.prepare("SELECT COUNT(*) FROM heart_rate")
        try stmt.step()
        return stmt.int(0)
    }

    @Test func rawCommitLivesOnlyInWAL() async throws {
        // Control: proves the copy technique can see a missing fold.
        let url = dir.appending(path: StrapStore.fileName)
        let store = try StrapStore(url: url)
        try await store.insert(SampleBatch(heartRate: [HeartRateSample(timestampMs: 1, bpm: 60)]))
        let db = try SQLiteConnection(path: url.path)
        try db.execute("PRAGMA wal_autocheckpoint=0")
        try db.execute("INSERT INTO heart_rate (ts_ms, bpm) VALUES (2, 61)")
        #expect(try heartRateRows(in: url) == 2)
        #expect(try heartRateRows(in: mainFileOnlyCopy(of: url)) == 1)
    }

    @Test func insertIsInMainFileBeforeReturn() async throws {
        let url = dir.appending(path: StrapStore.fileName)
        let store = try StrapStore(url: url)
        let written = try await store.insert(SampleBatch(heartRate: [HeartRateSample(timestampMs: 1_000, bpm: 58)]))
        #expect(written == 1)
        #expect(try heartRateRows(in: mainFileOnlyCopy(of: url)) == 1)
    }

    @Test func rowsSurviveRelaunchWithSidecarsDeleted() async throws {
        let url = dir.appending(path: StrapStore.fileName)
        do {
            let store = try StrapStore(url: url)
            try await store.insert(SampleBatch(
                heartRate: [HeartRateSample(timestampMs: 1_000, bpm: 58), HeartRateSample(timestampMs: 2_000, bpm: 61)],
                rr: [RRInterval(timestampMs: 1_000, milliseconds: 1_012)]
            ))
        }
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + sidecar)
        }
        let reopened = try StrapStore(url: url)
        let counts = try await reopened.counts()
        #expect(counts.heartRate == 2)
        #expect(counts.rr == 1)
        #expect(counts.latestHeartRateMs == 2_000)
    }

    private func eventRows(in url: URL) throws -> Int {
        let db = try SQLiteConnection(path: url.path)
        let stmt = try db.prepare("SELECT COUNT(*) FROM event")
        try stmt.step()
        return stmt.int(0)
    }

    @Test func eventInsertIsInMainFileBeforeReturn() async throws {
        let url = dir.appending(path: "events-\(UUID().uuidString)/\(StrapStore.fileName)")
        let store = try StrapStore(url: url)
        let event = StrapEvent(id: 57, unixSeconds: 1_700_000_000)
        let written = try await store.insert([event])
        #expect(written == 1)
        #expect(try eventRows(in: mainFileOnlyCopy(of: url)) == 1)
    }

    @Test func eventsSurviveRelaunchWithSidecarsDeleted() async throws {
        let url = dir.appending(path: "events-relaunch-\(UUID().uuidString)/\(StrapStore.fileName)")
        let fired = StrapEvent(id: 57, unixSeconds: 1_700_000_000)
        let haptics = StrapEvent(id: 60, unixSeconds: 1_700_000_000)
        do {
            let store = try StrapStore(url: url)
            try await store.insert([fired, haptics])
            try await store.insert([fired])
        }
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + sidecar)
        }
        let reopened = try StrapStore(url: url)
        #expect(try await reopened.events() == [fired, haptics])
    }

    @Test func duplicateSamplesAreIgnored() async throws {
        let store = try StrapStore(url: dir.appending(path: StrapStore.fileName))
        let batch = SampleBatch(heartRate: [HeartRateSample(timestampMs: 5, bpm: 70)])
        try await store.insert(batch)
        try await store.insert(batch)
        #expect(try await store.counts().heartRate == 1)
    }

    @Test func motionSurvivesRelaunchWithSidecarsDeleted() async throws {
        let url = dir.appending(path: "motion-\(UUID().uuidString)/\(StrapStore.fileName)")
        let night = MotionSample(timestampMs: 1_700_000_000_000, xMilliG: 0, yMilliG: 0, zMilliG: 1000, dynamicMilliG: 9, sleepByte: 0x20)
        let flagOnly = MotionSample(timestampMs: 1_700_000_001_000, xMilliG: nil, yMilliG: nil, zMilliG: nil, dynamicMilliG: nil, sleepByte: 0)
        do {
            let store = try StrapStore(url: url)
            try await store.insert(SampleBatch(motion: [night, flagOnly]))
            try await store.insert(SampleBatch(motion: [night]))
        }
        for sidecar in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + sidecar)
        }
        let reopened = try StrapStore(url: url)
        #expect(try await reopened.counts().motion == 1)
        #expect(try await reopened.motion(fromMs: night.timestampMs, throughMs: night.timestampMs) == [night])
        #expect(try await reopened.motion(fromMs: flagOnly.timestampMs, throughMs: flagOnly.timestampMs) == [flagOnly])
        let hr = HeartRateSample(timestampMs: night.timestampMs, bpm: 52)
        try await reopened.insert(SampleBatch(heartRate: [hr], rr: [RRInterval(timestampMs: night.timestampMs, milliseconds: 1100)]))
        #expect(try await reopened.heartRate(fromMs: night.timestampMs, throughMs: night.timestampMs) == [hr])
        #expect(try await reopened.rrIntervals(fromMs: 0, throughMs: night.timestampMs - 1).isEmpty)
    }

    @Test func anOlderFileGainsTheMotionTable() async throws {
        let url = dir.appending(path: "legacy-\(UUID().uuidString)/\(StrapStore.fileName)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let db = try SQLiteConnection(path: url.path)
        try db.execute("CREATE TABLE heart_rate (ts_ms INTEGER PRIMARY KEY, bpm INTEGER NOT NULL) WITHOUT ROWID")
        let store = try StrapStore(url: url)
        let sample = MotionSample(timestampMs: 1_700_000_000_000, xMilliG: 12, yMilliG: -4, zMilliG: 1000, dynamicMilliG: nil, sleepByte: nil)
        try await store.insert(SampleBatch(motion: [sample]))
        #expect(try await store.counts().motion == 1)
        #expect(try await store.motion(fromMs: sample.timestampMs, throughMs: sample.timestampMs) == [sample])
    }
}
