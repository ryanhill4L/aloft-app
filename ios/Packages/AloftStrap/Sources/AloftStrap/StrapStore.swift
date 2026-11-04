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

/// One second of strap motion, in milli-g (1000 = 1 g).
///
/// Gravity outside 0.25...4 g is left nil; heart rate from that second is
/// still stored. `dynamicMilliG` is the strap's own gravity-removed magnitude
/// when that float sits in 0...8 g. `sleepByte` is the raw WHOOP 5 v18 byte
/// at absolute offset 81 (high nibble: 0 wake, 1 still, 2 asleep, 3 up). It
/// is not a sleep stage. Nil on WHOOP 4 and on frames that do not reach it.
public struct MotionSample: Sendable, Equatable {
    public var timestampMs: Int64
    public var xMilliG: Int?
    public var yMilliG: Int?
    public var zMilliG: Int?
    public var dynamicMilliG: Int?
    public var sleepByte: UInt8?

    public init(timestampMs: Int64, xMilliG: Int?, yMilliG: Int?, zMilliG: Int?, dynamicMilliG: Int?, sleepByte: UInt8?) {
        self.timestampMs = timestampMs
        self.xMilliG = xMilliG
        self.yMilliG = yMilliG
        self.zMilliG = zMilliG
        self.dynamicMilliG = dynamicMilliG
        self.sleepByte = sleepByte
    }
}

public struct SampleBatch: Sendable, Equatable {
    public var heartRate: [HeartRateSample]
    public var rr: [RRInterval]
    public var motion: [MotionSample]

    public init(heartRate: [HeartRateSample] = [], rr: [RRInterval] = [], motion: [MotionSample] = []) {
        self.heartRate = heartRate
        self.rr = rr
        self.motion = motion
    }

    public var isEmpty: Bool { heartRate.isEmpty && rr.isEmpty && motion.isEmpty }
}

public struct StoreCounts: Sendable, Equatable {
    public var heartRate: Int
    public var rr: Int
    /// Rows that have a gravity vector. A sleep-byte-only second is not counted.
    public var motion: Int
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
            CREATE TABLE IF NOT EXISTS event (
                ts INTEGER NOT NULL,
                id INTEGER NOT NULL,
                PRIMARY KEY (ts, id)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS motion (
                ts_ms INTEGER PRIMARY KEY,
                x_mg INTEGER,
                y_mg INTEGER,
                z_mg INTEGER,
                dyn_mg INTEGER,
                sleep_byte INTEGER,
                CHECK (
                    (x_mg IS NULL AND y_mg IS NULL AND z_mg IS NULL)
                    OR (x_mg IS NOT NULL AND y_mg IS NOT NULL AND z_mg IS NOT NULL)
                ),
                CHECK (x_mg IS NOT NULL OR sleep_byte IS NOT NULL)
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
            let motion = try db.prepare("""
                INSERT OR IGNORE INTO motion (ts_ms, x_mg, y_mg, z_mg, dyn_mg, sleep_byte)
                VALUES (?, ?, ?, ?, ?, ?)
                """)
            for sample in batch.motion {
                let gravity: (Int64, Int64, Int64, Int64?)? = {
                    guard let x = sample.xMilliG, let y = sample.yMilliG, let z = sample.zMilliG else { return nil }
                    return (Int64(x), Int64(y), Int64(z), sample.dynamicMilliG.map(Int64.init))
                }()
                guard gravity != nil || sample.sleepByte != nil else { continue }
                motion.bind([
                    sample.timestampMs,
                    gravity?.0,
                    gravity?.1,
                    gravity?.2,
                    gravity?.3,
                    sample.sleepByte.map { Int64($0) },
                ])
                try motion.step()
                written += 1
            }
        }
        try foldWAL()
        return written
    }

    /// Writes strap events and folds them into the main file before returning.
    /// Same durability rule as `insert(_: SampleBatch)`.
    @discardableResult
    public func insert(_ events: [StrapEvent]) throws -> Int {
        guard !events.isEmpty else { return 0 }
        var written = 0
        try db.transaction {
            let row = try db.prepare("INSERT OR IGNORE INTO event (ts, id) VALUES (?, ?)")
            for event in events {
                row.bind([Int64(event.unixSeconds), Int64(event.id)])
                try row.step()
                written += 1
            }
        }
        try foldWAL()
        return written
    }

    public func events() throws -> [StrapEvent] {
        let rows = try db.prepare("SELECT ts, id FROM event ORDER BY ts, id")
        var out: [StrapEvent] = []
        while try rows.step() {
            out.append(StrapEvent(id: UInt8(rows.int(1)), unixSeconds: UInt32(rows.int(0))))
        }
        return out
    }

    public func counts() throws -> StoreCounts {
        let hr = try db.prepare("SELECT COUNT(*), MAX(ts_ms) FROM heart_rate")
        try hr.step()
        let rr = try db.prepare("SELECT COUNT(*) FROM rr_interval")
        try rr.step()
        let motion = try db.prepare("SELECT COUNT(*) FROM motion WHERE x_mg IS NOT NULL")
        try motion.step()
        let latest = hr.int(1)
        return StoreCounts(
            heartRate: hr.int(0),
            rr: rr.int(0),
            motion: motion.int(0),
            latestHeartRateMs: latest == 0 ? nil : Int64(latest)
        )
    }

    public func heartRate(fromMs: Int64, throughMs: Int64) throws -> [HeartRateSample] {
        let rows = try db.prepare("SELECT ts_ms, bpm FROM heart_rate WHERE ts_ms >= ? AND ts_ms <= ? ORDER BY ts_ms")
        rows.bind([fromMs, throughMs])
        var out: [HeartRateSample] = []
        while try rows.step() {
            out.append(HeartRateSample(timestampMs: Int64(rows.int(0)), bpm: rows.int(1)))
        }
        return out
    }

    public func rrIntervals(fromMs: Int64, throughMs: Int64) throws -> [RRInterval] {
        let rows = try db.prepare("SELECT ts_ms, ms FROM rr_interval WHERE ts_ms >= ? AND ts_ms <= ? ORDER BY ts_ms, ms")
        rows.bind([fromMs, throughMs])
        var out: [RRInterval] = []
        while try rows.step() {
            out.append(RRInterval(timestampMs: Int64(rows.int(0)), milliseconds: rows.int(1)))
        }
        return out
    }

    public func motion(fromMs: Int64, throughMs: Int64) throws -> [MotionSample] {
        let rows = try db.prepare("""
            SELECT ts_ms, x_mg, y_mg, z_mg, dyn_mg, sleep_byte
            FROM motion WHERE ts_ms >= ? AND ts_ms <= ? ORDER BY ts_ms
            """)
        rows.bind([fromMs, throughMs])
        var out: [MotionSample] = []
        while try rows.step() {
            let sleep = rows.intOrNil(5).flatMap { UInt8(exactly: $0) }
            out.append(MotionSample(
                timestampMs: Int64(rows.int(0)),
                xMilliG: rows.intOrNil(1),
                yMilliG: rows.intOrNil(2),
                zMilliG: rows.intOrNil(3),
                dynamicMilliG: rows.intOrNil(4),
                sleepByte: sleep
            ))
        }
        return out
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
