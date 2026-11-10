import Foundation

/// One week of wake times. Index 0 is Sunday, matching `Calendar` weekday 1.
/// Each day has its own on/off and minutes-from-midnight. A shared time is
/// just every enabled day carrying the same minutes.
public struct WeeklyWake: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable {
        public var enabled: Bool
        public var minutes: Int

        public init(enabled: Bool, minutes: Int) {
            self.enabled = enabled
            self.minutes = min(max(minutes, 0), 23 * 60 + 59)
        }
    }

    public var days: [Day]

    public init(days: [Day]) {
        self.days = days.count == 7
            ? days.map { Day(enabled: $0.enabled, minutes: $0.minutes) }
            : Self.offDays
    }

    public static let off = WeeklyWake(days: offDays)

    public static func everyDay(minutes: Int) -> WeeklyWake {
        WeeklyWake(days: (0..<7).map { _ in Day(enabled: true, minutes: minutes) })
    }

    /// Sets every day's clock. Leaves each day's on/off as it is.
    public func withEveryDay(minutes: Int) -> WeeklyWake {
        WeeklyWake(days: days.map { Day(enabled: $0.enabled, minutes: minutes) })
    }

    private static let offDays = (0..<7).map { _ in Day(enabled: false, minutes: 7 * 60) }
}

/// What to do with slot 1 given the week and the clock.
public enum WakeArming: Sendable, Equatable {
    case disarm
    case arm(Date)
}

/// The wake time Aloft arms on the strap. The window ends at that instant.
/// The 5/MG revision-4 record stores one epoch and has no window of its own.
public enum WakeSchedule {
    public static let window: TimeInterval = 30 * 60

    /// The next strictly future occurrence of `hour`:`minute` on `calendar`.
    public static func nextDeadline(hour: Int, minute: Int, now: Date, calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        let today = calendar.date(from: parts) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(24 * 60 * 60)
    }

    /// The next enabled day strictly after `now`. Nil when every day is off.
    /// Days are added on the calendar, so a DST shift does not skip or repeat a date.
    public static func nextDeadline(_ week: WeeklyWake, now: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: now)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard (1...7).contains(weekday) else { continue }
            let slot = week.days[weekday - 1]
            guard slot.enabled else { continue }
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = slot.minutes / 60
            parts.minute = slot.minutes % 60
            parts.second = 0
            guard let when = calendar.date(from: parts), when > now else { continue }
            return when
        }
        return nil
    }

    public static func decision(_ week: WeeklyWake, now: Date, calendar: Calendar = .current) -> WakeArming {
        guard let next = nextDeadline(week, now: now, calendar: calendar) else { return .disarm }
        return .arm(next)
    }

    public static func windowStart(_ deadline: Date) -> Date {
        deadline.addingTimeInterval(-window)
    }

    /// Epoch seconds from a 5/MG GET_ALARM body (`04`, slot, epoch). Nil when
    /// the body is not that record.
    public static func epoch(body: [UInt8]) -> UInt32? {
        guard body.count >= 6, body[0] == 0x04 else { return nil }
        return UInt32(body[2]) | UInt32(body[3]) << 8 | UInt32(body[4]) << 16 | UInt32(body[5]) << 24
    }

    /// True when the strap read back the same whole second we armed.
    public static func confirms(_ body: [UInt8], deadline: Date) -> Bool {
        guard let epoch = epoch(body: body) else { return false }
        return abs(Int64(epoch) - Int64(deadline.timeIntervalSince1970)) <= 2
    }
}
