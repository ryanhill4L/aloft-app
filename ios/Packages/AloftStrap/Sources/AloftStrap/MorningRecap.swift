import Foundation

/// The morning screen and the notification, from one detected night.
/// Stages stay absent: the detector does not produce light, deep, or REM.
public struct MorningRecap: Sendable, Equatable {
    public static let goalSeconds = 8 * 60 * 60

    public var asleepSeconds: Int
    public var goalSeconds: Int
    public var efficiency: Double?
    public var onsetMs: Int64?
    public var wakeMs: Int64?
    public var restingBPM: Int?
    public var averageBPM: Int?
    public var stageNote: String
    public var hasStages: Bool

    public init(asleepSeconds: Int, goalSeconds: Int = MorningRecap.goalSeconds, efficiency: Double?, onsetMs: Int64?, wakeMs: Int64?, restingBPM: Int?, averageBPM: Int?, stageNote: String, hasStages: Bool) {
        self.asleepSeconds = asleepSeconds
        self.goalSeconds = goalSeconds
        self.efficiency = efficiency
        self.onsetMs = onsetMs
        self.wakeMs = wakeMs
        self.restingBPM = restingBPM
        self.averageBPM = averageBPM
        self.stageNote = stageNote
        self.hasStages = hasStages
    }

    public var notificationTitle: String { "Last night" }

    public var notificationBody: String {
        var line = "\(Self.hoursMinutes(asleepSeconds)) asleep of \(Self.hoursMinutes(goalSeconds))"
        if let efficiency {
            line += ". Efficiency \(Int((efficiency * 100).rounded()))%"
        }
        return line
    }

    /// A finished night posts once per onset. An open night stays on the screen only.
    public func shouldNotify(alreadyNotifiedOnsetMs: Int64?) -> Bool {
        guard let onsetMs, wakeMs != nil else { return false }
        return alreadyNotifiedOnsetMs != onsetMs
    }

    public static func hoursMinutes(_ seconds: Int) -> String {
        let hours = max(seconds, 0) / 3600
        let minutes = (max(seconds, 0) % 3600) / 60
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }

    /// Nil when the night never started. Heart rate is the samples between
    /// onset and wake. Resting is the lowest of those; average is their mean.
    public static func from(night: SleepNight, heartRate: [HeartRateSample]) -> MorningRecap? {
        guard let onset = night.onsetMs else { return nil }
        let end = night.wakeMs ?? Int64.max
        let span = heartRate.filter { $0.bpm > 0 && $0.timestampMs >= onset && $0.timestampMs < end }
        let average: Int? = span.isEmpty ? nil : Int((Double(span.reduce(0) { $0 + $1.bpm }) / Double(span.count)).rounded())
        return MorningRecap(
            asleepSeconds: Int(night.asleepMs / 1000),
            efficiency: night.efficiency,
            onsetMs: onset,
            wakeMs: night.wakeMs,
            restingBPM: span.map(\.bpm).min(),
            averageBPM: average,
            stageNote: night.note,
            hasStages: night.stages != nil
        )
    }
}
