import Foundation
import Testing
@testable import AloftStrap

@Suite struct WakeScheduleTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: 0))!
    }

    @Test func aLaterTimeTodayIsTheDeadline() {
        let deadline = WakeSchedule.nextDeadline(hour: 7, minute: 0, now: date(4, 6, 0), calendar: calendar)
        #expect(deadline == date(4, 7, 0))
        #expect(WakeSchedule.windowStart(deadline) == date(4, 6, 30))
    }

    @Test func aTimeAlreadyPassedIsTomorrow() {
        let deadline = WakeSchedule.nextDeadline(hour: 7, minute: 0, now: date(4, 8, 0), calendar: calendar)
        #expect(deadline == date(5, 7, 0))
    }

    @Test func anEnabledWeekdayLaterTodayIsThatMorning() {
        // 4 Nov 2026 is a Wednesday. Wednesday is weekday 4, index 3.
        var week = WeeklyWake.off
        week.days[3] = .init(enabled: true, minutes: 7 * 60)
        let next = WakeSchedule.nextDeadline(week, now: date(4, 6, 0), calendar: calendar)
        #expect(next == date(4, 7, 0))
        #expect(WakeSchedule.decision(week, now: date(4, 6, 0), calendar: calendar) == .arm(date(4, 7, 0)))
    }

    @Test func aTimeAlreadyPassedRollsToTheNextEnabledDay() {
        var week = WeeklyWake.off
        week.days[3] = .init(enabled: true, minutes: 7 * 60) // Wednesday
        week.days[5] = .init(enabled: true, minutes: 8 * 60 + 30) // Friday
        let next = WakeSchedule.nextDeadline(week, now: date(4, 8, 0), calendar: calendar)
        #expect(next == date(6, 8, 30))
    }

    @Test func aPerDayTimeIsKept() {
        var week = WeeklyWake.everyDay(minutes: 7 * 60)
        week.days[2].minutes = 8 * 60 // Tuesday
        let next = WakeSchedule.nextDeadline(week, now: date(2, 7, 30), calendar: calendar)
        #expect(calendar.component(.day, from: next!) == 3)
        #expect(calendar.component(.hour, from: next!) == 8)
    }

    @Test func everyDayOffDisarms() {
        #expect(WakeSchedule.nextDeadline(WeeklyWake.off, now: date(4, 6, 0), calendar: calendar) == nil)
        #expect(WakeSchedule.decision(.off, now: date(4, 6, 0), calendar: calendar) == .disarm)
    }

    @Test func springForwardDoesNotSkipTheMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 0))!
        let next = WakeSchedule.nextDeadline(.everyDay(minutes: 2 * 60 + 30), now: now, calendar: calendar)
        #expect(next! > now)
        #expect(calendar.component(.day, from: next!) == 8)
        #expect(calendar.component(.hour, from: next!) == 3)
        #expect(calendar.component(.minute, from: next!) == 30)
    }

    @Test func fallBackKeepsTheNextMorningAtSeven() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // Sunday 1 Nov 2026, after the 2:00 fallback. Only Monday is on.
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 3, minute: 0))!
        var week = WeeklyWake.off
        week.days[1] = .init(enabled: true, minutes: 7 * 60) // Monday
        let next = WakeSchedule.nextDeadline(week, now: now, calendar: calendar)
        #expect(calendar.component(.day, from: next!) == 2)
        #expect(calendar.component(.hour, from: next!) == 7)
        #expect(calendar.component(.minute, from: next!) == 0)
    }

    @Test func readbackMatchesTheArmedSecond() {
        let deadline = date(4, 7, 0)
        let unix = UInt32(deadline.timeIntervalSince1970)
        var body: [UInt8] = [0x04, 0x01, UInt8(unix & 0xFF), UInt8((unix >> 8) & 0xFF), UInt8((unix >> 16) & 0xFF), UInt8(unix >> 24)]
        body += [UInt8](repeating: 0, count: 15)
        #expect(WakeSchedule.epoch(body: body) == unix)
        #expect(WakeSchedule.confirms(body, deadline: deadline))
        body[2] = body[2] &+ 30
        #expect(!WakeSchedule.confirms(body, deadline: deadline))
        #expect(WakeSchedule.epoch(body: [0x01, 0, 0, 0, 0, 0]) == nil)
    }
}
