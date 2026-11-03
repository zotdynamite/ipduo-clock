import XCTest
@testable import IpduoClockCore

final class AlarmScheduleTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testOneShotLaterToday() {
        let from = date(2026, 11, 2, 10, 0)
        let next = AlarmScheduling.nextFireDate(hour: 11, minute: 15, repeatDays: [], from: from, calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 2, 11, 15))
    }

    func testOneShotRollsToTomorrow() {
        let from = date(2026, 11, 2, 10, 0)
        let next = AlarmScheduling.nextFireDate(hour: 9, minute: 30, repeatDays: [], from: from, calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 3, 9, 30))
    }

    func testOneShotAtTheExactMomentWaitsUntilTomorrow() {
        let from = date(2026, 11, 2, 9, 30)
        let next = AlarmScheduling.nextFireDate(hour: 9, minute: 30, repeatDays: [], from: from, calendar: calendar)
        XCTAssertEqual(next, date(2026, 11, 3, 9, 30))
    }

    func testRepeatingPicksTheNextListedWeekday() {
        let from = date(2026, 11, 2, 10, 0)
        let monday = calendar.component(.weekday, from: from)
        XCTAssertEqual(monday, 2, "2 Nov 2026 is a Monday in the Gregorian calendar")
        let wednesday = monday + 2
        let next = AlarmScheduling.nextFireDate(
            hour: 9,
            minute: 0,
            repeatDays: [monday, wednesday],
            from: from,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 11, 4, 9, 0))
    }

    func testRepeatingSameDayWhenTimeIsStillAhead() {
        let from = date(2026, 11, 2, 10, 0)
        let monday = calendar.component(.weekday, from: from)
        let next = AlarmScheduling.nextFireDate(
            hour: 10,
            minute: 30,
            repeatDays: [monday],
            from: from,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 11, 2, 10, 30))
    }

    func testRepeatingSkipsToNextWeek() {
        let from = date(2026, 11, 2, 10, 0)
        let monday = calendar.component(.weekday, from: from)
        let next = AlarmScheduling.nextFireDate(
            hour: 9,
            minute: 0,
            repeatDays: [monday],
            from: from,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 11, 9, 9, 0))
    }

    func testTriggersForRepeatingAndOneShot() {
        let from = date(2026, 11, 2, 10, 0)
        let once = AlarmScheduling.triggers(hour: 11, minute: 0, repeatDays: [], from: from, calendar: calendar)
        XCTAssertEqual(once.count, 1)
        XCTAssertEqual(once[0].repeats, false)
        XCTAssertEqual(once[0].dateComponents.day, 2)
        XCTAssertEqual(once[0].dateComponents.hour, 11)

        let weekly = AlarmScheduling.triggers(hour: 7, minute: 5, repeatDays: [2, 4, 6], from: from, calendar: calendar)
        XCTAssertEqual(weekly.map(\.repeats), [true, true, true])
        XCTAssertEqual(weekly.map { $0.dateComponents.weekday }, [2, 4, 6])
        XCTAssertEqual(weekly.map { $0.dateComponents.hour }, [7, 7, 7])
        XCTAssertTrue(weekly.allSatisfy { $0.dateComponents.day == nil })
    }

    func testSnoozeAndDisabledAlarm() {
        let from = date(2026, 11, 2, 10, 0)
        XCTAssertEqual(AlarmScheduling.snoozeDate(from: from, minutes: 9), date(2026, 11, 2, 10, 9))

        let alarm = Alarm(hour: 11, minute: 0, isEnabled: false)
        XCTAssertNil(alarm.nextFire(from: from, calendar: calendar))
        XCTAssertEqual(alarm.nextFire(from: from, calendar: calendar, respectEnabled: false), date(2026, 11, 2, 11, 0))
    }

    func testRepeatSummaryAndJSONRoundTrip() {
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        XCTAssertEqual(AlarmScheduling.repeatSummary(weekdays: [], symbols: symbols), "Once")
        XCTAssertEqual(AlarmScheduling.repeatSummary(weekdays: Set(1...7), symbols: symbols), "Every day")
        XCTAssertEqual(AlarmScheduling.repeatSummary(weekdays: [2, 3, 4, 5, 6], symbols: symbols), "Weekdays")
        XCTAssertEqual(AlarmScheduling.repeatSummary(weekdays: [1, 7], symbols: symbols), "Weekends")
        XCTAssertEqual(AlarmScheduling.repeatSummary(weekdays: [2, 4], symbols: symbols), "Mon Wed")

        let alarm = Alarm(
            hour: 6,
            minute: 45,
            repeatWeekdays: [2, 4],
            label: "Dawn",
            snoozeMinutes: 5,
            sound: .song(id: "song-1", title: "First Light", artist: "Harbor")
        )
        let data = try! JSONEncoder().encode(alarm)
        let decoded = try! JSONDecoder().decode(Alarm.self, from: data)
        XCTAssertEqual(decoded, alarm)
    }

    func testNewYorkOffsetChangesWithDaylightSaving() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let utc = TimeZone(secondsFromGMT: 0)!
        let winter = date(2026, 1, 15, 12, 0)
        let summer = date(2026, 7, 15, 12, 0)
        XCTAssertEqual(newYork.secondsFromGMT(for: winter), -5 * 3600)
        XCTAssertEqual(newYork.secondsFromGMT(for: summer), -4 * 3600)
        let winterOffset = WorldTime.offset(from: utc, to: newYork, at: winter)
        let summerOffset = WorldTime.offset(from: utc, to: newYork, at: summer)
        XCTAssertEqual(winterOffset.seconds, -5 * 3600)
        XCTAssertEqual(summerOffset.seconds, -4 * 3600)
    }
}
