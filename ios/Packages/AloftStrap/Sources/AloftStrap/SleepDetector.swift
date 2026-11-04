import Foundation

/// One minute of a night, classified from heart rate, beat intervals, and motion.
///
/// `restless` is a stir: more motion than still sleep, less than awake. It is
/// not WHOOP's light stage. Light, deep, and REM are not classified at all.
public struct SleepEpoch: Sendable, Equatable {
    public var startMs: Int64
    public var kind: Kind

    public enum Kind: String, Sendable, Equatable {
        case awake, restless, asleep
    }

    public init(startMs: Int64, kind: Kind) {
        self.startMs = startMs
        self.kind = kind
    }
}

/// What a stored night supports. `stages` stays nil: these signals do not
/// support light, deep, and REM.
public struct SleepNight: Sendable, Equatable {
    public var inBedStartMs: Int64?
    public var onsetMs: Int64?
    /// Set only when a run of awake minutes ends the night. The last sample
    /// is not treated as a wake.
    public var wakeMs: Int64?
    public var asleepMs: Int64
    public var inBedMs: Int64?
    /// Time asleep divided by time in bed. Nil until both ends exist.
    public var efficiency: Double?
    public var epochs: [SleepEpoch]
    public var stages: [String]?
    public var note: String

    public static let stageNote = "Light, deep, and REM are not estimated. Heart rate, beat intervals, and motion can separate still sleep from waking. They are not a sleep stage."
}

/// Early buzz inside the half hour before a deadline. `.hold` leaves the
/// strap's own alarm at that deadline alone.
public enum SmartWake: Sendable, Equatable {
    case hold
    case buzzEarly
}

/// On-device sleep from stored strap rows. No Bluetooth and no network.
public enum SleepDetector {
    public static let epochMs: Int64 = 60_000
    public static let onsetRun = 10
    public static let wakeRun = 5
    /// Still sleep, in milli-g. 15 is 0.015 g.
    public static let stillDynamicMilliG = 15
    /// Above this, the minute is awake. Between still and this is a stir.
    public static let restlessDynamicMilliG = 40
    public static let asleepHeartMax = 75
    public static let awakeHeartMin = 90
    public static let windowMs: Int64 = 30 * 60 * 1000

    public static func detect(
        heartRate: [HeartRateSample],
        rr: [RRInterval],
        motion: [MotionSample]
    ) -> SleepNight {
        let epochs = epochs(heartRate: heartRate, rr: rr, motion: motion)
        guard let onsetIndex = runStart(epochs, kind: .asleep, length: onsetRun) else {
            return SleepNight(
                inBedStartMs: nil, onsetMs: nil, wakeMs: nil, asleepMs: 0, inBedMs: nil,
                efficiency: nil, epochs: epochs, stages: nil,
                note: epochs.isEmpty ? "No heart rate or motion in this window." : SleepNight.stageNote
            )
        }
        let onset = epochs[onsetIndex]
        let inBedIndex = inBedStart(epochs, onset: onsetIndex)
        let wakeIndex = runStart(Array(epochs.dropFirst(onsetIndex + 1)), kind: .awake, length: wakeRun)
            .map { onsetIndex + 1 + $0 }
        let wake = wakeIndex.map { epochs[$0] }
        let end = wakeIndex ?? epochs.count
        let asleepCount = epochs[onsetIndex..<end].filter { $0.kind == .asleep }.count
        let asleepMs = Int64(asleepCount) * epochMs
        let inBedMs = wake.map { $0.startMs - epochs[inBedIndex].startMs }
        let efficiency: Double? = {
            guard let inBedMs, inBedMs > 0 else { return nil }
            return Double(asleepMs) / Double(inBedMs)
        }()
        return SleepNight(
            inBedStartMs: epochs[inBedIndex].startMs,
            onsetMs: onset.startMs,
            wakeMs: wake?.startMs,
            asleepMs: asleepMs,
            inBedMs: inBedMs,
            efficiency: efficiency,
            epochs: epochs,
            stages: nil,
            note: SleepNight.stageNote
        )
    }

    /// Minutes that have motion. A gap minute is omitted, and a gap breaks a run.
    public static func epochs(
        heartRate: [HeartRateSample],
        rr: [RRInterval],
        motion: [MotionSample]
    ) -> [SleepEpoch] {
        var hr: [Int64: [Int]] = [:]
        var beats: [Int64: [Int]] = [:]
        var dynamic: [Int64: [Int]] = [:]
        var gravity: [Int64: [(Int, Int, Int)]] = [:]
        for sample in heartRate where sample.bpm > 0 {
            hr[bucket(sample.timestampMs), default: []].append(sample.bpm)
        }
        for sample in rr where sample.milliseconds > 0 {
            beats[bucket(sample.timestampMs), default: []].append(sample.milliseconds)
        }
        for sample in motion {
            let key = bucket(sample.timestampMs)
            if let value = sample.dynamicMilliG { dynamic[key, default: []].append(value) }
            if let x = sample.xMilliG, let y = sample.yMilliG, let z = sample.zMilliG {
                gravity[key, default: []].append((x, y, z))
            }
        }
        let keys = Set(hr.keys).union(beats.keys).union(dynamic.keys).union(gravity.keys).sorted()
        var previousGravity: (Int, Int, Int)?
        var out: [SleepEpoch] = []
        for key in keys {
            let bpm = median(hr[key] ?? []) ?? beats[key].flatMap(restingRate)
            let motionLevel = median(dynamic[key] ?? []) ?? gravityDelta(gravity[key] ?? [], previous: previousGravity)
            if let mean = meanGravity(gravity[key] ?? []) { previousGravity = mean }
            guard let motionLevel else { continue }
            out.append(SleepEpoch(startMs: key * epochMs, kind: kind(dynamic: motionLevel, bpm: bpm)))
        }
        return out
    }

    /// Inside the 30 minutes before `deadlineMs`, buzz early when the wearer
    /// stirs or wakes after having been asleep. Outside that window, hold.
    public static func smartWake(epochs: [SleepEpoch], nowMs: Int64, deadlineMs: Int64) -> SmartWake {
        let windowStart = deadlineMs - windowMs
        guard nowMs >= windowStart, nowMs < deadlineMs else { return .hold }
        let lookback = windowStart - Int64(onsetRun) * epochMs
        let recent = epochs.filter { $0.startMs >= lookback && $0.startMs <= nowMs }
        guard let current = recent.last, current.kind == .awake || current.kind == .restless else { return .hold }
        guard recent.contains(where: { $0.kind == .asleep }) else { return .hold }
        return .buzzEarly
    }

    private static func bucket(_ ms: Int64) -> Int64 { ms.floorDiv(epochMs) }

    private static func kind(dynamic: Int, bpm: Int?) -> SleepEpoch.Kind {
        if dynamic > restlessDynamicMilliG || (bpm ?? 0) >= awakeHeartMin { return .awake }
        if dynamic <= stillDynamicMilliG {
            if let bpm, bpm > asleepHeartMax { return .restless }
            return .asleep
        }
        return .restless
    }

    private static func restingRate(_ intervals: [Int]) -> Int? {
        guard let mid = median(intervals), mid > 0 else { return nil }
        return 60_000 / mid
    }

    private static func meanGravity(_ samples: [(Int, Int, Int)]) -> (Int, Int, Int)? {
        guard !samples.isEmpty else { return nil }
        let n = samples.count
        return (
            samples.reduce(0) { $0 + $1.0 } / n,
            samples.reduce(0) { $0 + $1.1 } / n,
            samples.reduce(0) { $0 + $1.2 } / n
        )
    }

    /// Distance from the previous minute's gravity, used when the strap did
    /// not report a dynamic magnitude. Nil on the first minute.
    private static func gravityDelta(_ samples: [(Int, Int, Int)], previous: (Int, Int, Int)?) -> Int? {
        guard let previous, let mean = meanGravity(samples) else { return nil }
        let dx = mean.0 - previous.0
        let dy = mean.1 - previous.1
        let dz = mean.2 - previous.2
        return Int((Double(dx * dx + dy * dy + dz * dz)).squareRoot().rounded())
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// First index of `length` adjacent minutes of `kind`. A missing minute breaks the run.
    private static func runStart(_ epochs: [SleepEpoch], kind: SleepEpoch.Kind, length: Int) -> Int? {
        var run = 0
        var start = 0
        var previous: Int64?
        for (index, epoch) in epochs.enumerated() {
            let follows = previous == nil || epoch.startMs - previous! == epochMs
            if epoch.kind == kind, follows {
                if run == 0 { start = index }
                run += 1
                if run >= length { return start }
            } else if epoch.kind == kind {
                start = index
                run = 1
            } else {
                run = 0
            }
            previous = epoch.startMs
        }
        return nil
    }

    /// Walk back from onset across asleep and restless minutes. An awake minute
    /// or a gap ends the in-bed stretch.
    private static func inBedStart(_ epochs: [SleepEpoch], onset: Int) -> Int {
        var index = onset
        while index > 0 {
            let previous = epochs[index - 1]
            let adjacent = epochs[index].startMs - previous.startMs == epochMs
            guard adjacent, previous.kind != .awake else { break }
            index -= 1
        }
        return index
    }
}

private extension Int64 {
    func floorDiv(_ divisor: Int64) -> Int64 {
        let q = self / divisor
        return self % divisor >= 0 ? q : q - 1
    }
}
