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

    @Test func duplicateSamplesAreIgnored() async throws {
        let store = try StrapStore(url: dir.appending(path: StrapStore.fileName))
        let batch = SampleBatch(heartRate: [HeartRateSample(timestampMs: 5, bpm: 70)])
        try await store.insert(batch)
        try await store.insert(batch)
        #expect(try await store.counts().heartRate == 1)
    }
}
