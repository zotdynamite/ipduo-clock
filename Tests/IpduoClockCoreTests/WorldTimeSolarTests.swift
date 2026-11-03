import XCTest
@testable import IpduoClockCore

final class WorldTimeSolarTests: XCTestCase {
    func testDayShiftAcrossMidnight() {
        let london = TimeZone(identifier: "Europe/London")!
        let newYork = TimeZone(identifier: "America/New_York")!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        // 15 Jan 2026 02:00 UTC is 02:00 in London (GMT) and 21:00 the previous evening in New York.
        let moment = utc.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 2))!
        let offset = WorldTime.offset(from: london, to: newYork, at: moment)
        XCTAssertEqual(offset.dayShift, -1)
        XCTAssertEqual(offset.seconds, -5 * 3600)
        XCTAssertEqual(offset.dayLabel, "Yesterday")
        XCTAssertEqual(offset.hourMinuteLabel, "−5HRS")
        XCTAssertEqual(offset.summary, "Yesterday, −5HRS")
    }

    func testHalfHourOffsetLabel() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let moment = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))!
        let offset = WorldTime.offset(from: utc, to: kolkata, at: moment)
        XCTAssertEqual(offset.seconds, (5 * 3600) + (30 * 60))
        XCTAssertEqual(offset.hourMinuteLabel, "+5:30")
    }

    func testSameTimeLabel() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let offset = WorldTime.offset(from: utc, to: utc, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(offset.seconds, 0)
        XCTAssertEqual(offset.dayShift, 0)
        XCTAssertEqual(offset.summary, "Today, same time")
    }

    func testCatalogCitiesHaveRealTimeZones() {
        XCTAssertGreaterThan(CityCatalog.all.count, 30)
        for city in CityCatalog.all {
            XCTAssertNotNil(city.timeZone, city.name)
            XCTAssertEqual(city.id, "\(city.name)|\(city.timeZoneIdentifier)")
        }
        XCTAssertEqual(CityCatalog.all.map(\.id).count, Set(CityCatalog.all.map(\.id)).count)
        XCTAssertNotNil(WorldTime.match(timeZone: TimeZone(identifier: "Asia/Tokyo")!))
    }

    func testJuneDayIsLongerThanDecemberInNewYork() {
        let zone = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let june = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let december = calendar.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!
        let summer = Solar.daylight(latitude: 40.7128, longitude: -74.0060, on: june, timeZone: zone)
        let winter = Solar.daylight(latitude: 40.7128, longitude: -74.0060, on: december, timeZone: zone)
        XCTAssertNotNil(summer)
        XCTAssertNotNil(winter)
        XCTAssertGreaterThan(summer!.length, 14 * 3600)
        XCTAssertLessThan(winter!.length, 10 * 3600)
        XCTAssertLessThan(summer!.sunrise, summer!.sunset)
    }

    func testEquatorDayIsNearTwelveHours() {
        let zone = TimeZone(identifier: "Asia/Singapore")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        let daylight = Solar.daylight(latitude: 1.3521, longitude: 103.8198, on: date, timeZone: zone)
        XCTAssertNotNil(daylight)
        XCTAssertEqual(daylight!.length, 12 * 3600, accuracy: 25 * 60)
    }

    func testPolarSummerDoesNotInventASunrise() {
        let zone = TimeZone(identifier: "Arctic/Longyearbyen") ?? TimeZone(secondsFromGMT: 3600)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        XCTAssertNil(Solar.daylight(latitude: 78.22, longitude: 15.65, on: date, timeZone: zone))
    }

    func testDaylightFlagAndPhases() {
        let zone = TimeZone(identifier: "Europe/Paris")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let noon = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 1))!
        XCTAssertTrue(WorldTime.isDaylight(at: noon, timeZone: zone, latitude: 48.8566, longitude: 2.3522))
        XCTAssertFalse(WorldTime.isDaylight(at: midnight, timeZone: zone, latitude: 48.8566, longitude: 2.3522))

        let daylight = Solar.daylight(latitude: 48.8566, longitude: 2.3522, on: noon, timeZone: zone)!
        XCTAssertEqual(Solar.phase(at: daylight.sunrise.addingTimeInterval(-3 * 3600), daylight: daylight), .night)
        XCTAssertEqual(Solar.phase(at: daylight.sunrise.addingTimeInterval(-10 * 60), daylight: daylight), .dawn)
        XCTAssertEqual(Solar.phase(at: daylight.sunrise.addingTimeInterval(2 * 3600), daylight: daylight), .morning)
        XCTAssertEqual(Solar.phase(at: daylight.sunset.addingTimeInterval(-2 * 3600), daylight: daylight), .afternoon)
        XCTAssertEqual(Solar.phase(at: daylight.sunset.addingTimeInterval(10 * 60), daylight: daylight), .dusk)
        XCTAssertEqual(Solar.phase(at: daylight.sunset.addingTimeInterval(2 * 3600), daylight: daylight), .night)
        XCTAssertEqual(Solar.hourPhase(at: midnight, timeZone: zone), .night)
    }
}
