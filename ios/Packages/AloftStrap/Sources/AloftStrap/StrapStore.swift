import Foundation

/// One heart-rate reading, from history or from the live 0x2A37 stream.
public struct HeartRateSample: Sendable, Equatable {
    public var timestampMs: Int64
    public var bpm: Int

    public init(timestampMs: Int64, bpm: Int) {
        self.timestampMs = timestampMs
        self.bpm = bpm
    }
}

/// One beat-to-beat interval.
public struct RRInterval: Sendable, Equatable {
    public var timestampMs: Int64
    public var milliseconds: Int

    public init(timestampMs: Int64, milliseconds: Int) {
        self.timestampMs = timestampMs
        self.milliseconds = milliseconds
    }
}

public struct SampleBatch: Sendable, Equatable {
    public var heartRate: [HeartRateSample]
    public var rr: [RRInterval]

    public init(heartRate: [HeartRateSample] = [], rr: [RRInterval] = []) {
        self.heartRate = heartRate
        self.rr = rr
    }

    public var isEmpty: Bool { heartRate.isEmpty && rr.isEmpty }
}

public struct StoreCounts: Sendable, Equatable {
    public var heartRate: Int
    public var rr: Int
    public var latestHeartRateMs: Int64?
}

/// The on-device store. Health data never leaves this file.
///
/// `insert` folds the WAL into the main database file before it returns, so a
/// caller that acks the strap after `insert` can never ack rows that live only
/// in `-wal` (the fork lost history that way; see docs/noop-reference.md).
public actor StrapStore {
    public static let fileName = "aloft.sqlite"

    public nonisolated let url: URL
    private let db: SQLiteConnection

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteConnection(path: url.path)
        try db.execute("PRAGMA journal_mode=WAL")
        try db.execute("PRAGMA synchronous=FULL")
        try db.execute("""
            CREATE TABLE IF NOT EXISTS heart_rate (
                ts_ms INTEGER PRIMARY KEY,
                bpm INTEGER NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS rr_interval (
                ts_ms INTEGER NOT NULL,
                ms INTEGER NOT NULL,
                PRIMARY KEY (ts_ms, ms)
            ) WITHOUT ROWID;
            """)
        Self.protect(url)
    }

    /// Writes the batch and folds it into the main file. Returns rows written.
    /// Throws without folding if the write fails; the caller must not ack.
    @discardableResult
    public func insert(_ batch: SampleBatch) throws -> Int {
        guard !batch.isEmpty else { return 0 }
        var written = 0
        try db.transaction {
            let hr = try db.prepare("INSERT OR IGNORE INTO heart_rate (ts_ms, bpm) VALUES (?, ?)")
            for sample in batch.heartRate {
                hr.bind([sample.timestampMs, Int64(sample.bpm)])
                try hr.step()
                written += 1
            }
            let rr = try db.prepare("INSERT OR IGNORE INTO rr_interval (ts_ms, ms) VALUES (?, ?)")
            for interval in batch.rr {
                rr.bind([interval.timestampMs, Int64(interval.milliseconds)])
                try rr.step()
                written += 1
            }
        }
        try foldWAL()
        return written
    }

    public func counts() throws -> StoreCounts {
        let hr = try db.prepare("SELECT COUNT(*), MAX(ts_ms) FROM heart_rate")
        try hr.step()
        let rr = try db.prepare("SELECT COUNT(*) FROM rr_interval")
        try rr.step()
        let latest = hr.int(1)
        return StoreCounts(heartRate: hr.int(0), rr: rr.int(0), latestHeartRateMs: latest == 0 ? nil : Int64(latest))
    }

    /// Truncates the WAL. Call when the app goes to the background.
    public func checkpointTruncate() throws {
        _ = try db.checkpoint("TRUNCATE")
        Self.protect(url)
    }

    private func foldWAL() throws {
        if try db.checkpoint("PASSIVE") > 0 {
            _ = try db.checkpoint("FULL")
        }
        Self.protect(url)
    }

    /// A locked phone must still be able to open the store after first unlock.
    private static func protect(_ url: URL) {
        #if os(iOS)
        let paths = [url.deletingLastPathComponent().path, url.path, url.path + "-wal", url.path + "-shm"]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: path
            )
        }
        #endif
    }
}
