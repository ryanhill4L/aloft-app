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
