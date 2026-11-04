import Foundation

/// The wake time Aloft arms on the strap. The window ends at this instant.
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
