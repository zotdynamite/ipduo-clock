import Foundation

/// Sunrise and sunset for a civil day, plus the ambient phases derived from them.
public enum Solar {
    public struct Daylight: Equatable {
        public var sunrise: Date
        public var sunset: Date

        public init(sunrise: Date, sunset: Date) {
            self.sunrise = sunrise
            self.sunset = sunset
        }

        public var length: TimeInterval {
            sunset.timeIntervalSince(sunrise)
        }
    }

    public enum Phase: String, Equatable, CaseIterable {
        case night
        case dawn
        case morning
        case afternoon
        case dusk
    }

    /// Official sunrise/sunset (zenith 90.833°). Nil during polar day or polar night.
    public static func daylight(
        latitude: Double,
        longitude: Double,
        on date: Date,
        timeZone: TimeZone
    ) -> Daylight? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        guard let riseUT = universalHours(latitude: latitude, longitude: longitude, year: year, month: month, day: day, rising: true),
              let setUT = universalHours(latitude: latitude, longitude: longitude, year: year, month: month, day: day, rising: false),
              let sunrise = dateFromUniversalHours(riseUT, year: year, month: month, day: day),
              var sunset = dateFromUniversalHours(setUT, year: year, month: month, day: day)
        else { return nil }
        // The USNO approximation returns sunset a day early when it falls after UTC midnight,
        // and a negative hour when the event is late on the previous UTC date. Shift sunset
        // forward once so it is the next occurrence after sunrise, still inside one day.
        if sunset <= sunrise {
            sunset = sunset.addingTimeInterval(24 * 3600)
        }
        let length = sunset.timeIntervalSince(sunrise)
        guard length > 0, length <= 24 * 3600 else { return nil }
        return Daylight(sunrise: sunrise, sunset: sunset)
    }

    /// Where the moment sits relative to sunrise and sunset.
    /// Dawn begins 45 minutes before sunrise; dusk lasts 40 minutes after sunset.
    public static func phase(at date: Date, daylight: Daylight?) -> Phase {
        guard let daylight else {
            return hourPhase(at: date)
        }
        let time = date.timeIntervalSince1970
        let rise = daylight.sunrise.timeIntervalSince1970
        let set = daylight.sunset.timeIntervalSince1970
        if time < rise - 45 * 60 { return .night }
        if time < rise + 20 * 60 { return .dawn }
        if time < rise + 5 * 60 * 60 { return .morning }
        if time < set - 45 * 60 { return .afternoon }
        if time < set + 40 * 60 { return .dusk }
        return .night
    }

    public static func phase(
        at date: Date,
        timeZone: TimeZone,
        latitude: Double?,
        longitude: Double?
    ) -> Phase {
        let daylight: Daylight?
        if let latitude, let longitude {
            daylight = self.daylight(latitude: latitude, longitude: longitude, on: date, timeZone: timeZone)
        } else {
            daylight = nil
        }
        if daylight == nil, latitude != nil {
            return hourPhase(at: date, timeZone: timeZone)
        }
        return phase(at: date, daylight: daylight)
    }

    /// Hour-of-day fallback when a coordinate has no sunrise (polar regions) or is unknown.
    public static func hourPhase(at date: Date, timeZone: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current) -> Phase {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<7: return .dawn
        case 7..<11: return .morning
        case 11..<17: return .afternoon
        case 17..<20: return .dusk
        default: return .night
        }
    }

    // MARK: - NOAA-style sunrise

    /// Universal Time hours, possibly outside 0..<24 so the caller can shift the civil day.
    private static func universalHours(
        latitude: Double,
        longitude: Double,
        year: Int,
        month: Int,
        day: Int,
        rising: Bool
    ) -> Double? {
        let zenith = 90.833
        let n = dayOfYear(year: year, month: month, day: day)
        let lngHour = longitude / 15
        let t = Double(n) + (((rising ? 6.0 : 18.0) - lngHour) / 24)
        let m = (0.9856 * t) - 3.289
        var l = m + (1.916 * sind(m)) + (0.020 * sind(2 * m)) + 282.634
        l = wrap360(l)

        var ra = atand(0.91764 * tand(l))
        let lQuadrant = floor(l / 90) * 90
        let raQuadrant = floor(ra / 90) * 90
        ra += (lQuadrant - raQuadrant)
        ra /= 15

        let sinDec = 0.39782 * sind(l)
        let cosDec = cosd(asind(sinDec))
        let cosLat = cosd(latitude)
        guard abs(cosDec * cosLat) > 0.000_001 else { return nil }
        let cosH = (cosd(zenith) - (sinDec * sind(latitude))) / (cosDec * cosLat)
        if cosH > 1 || cosH < -1 { return nil }

        var h = rising ? 360 - acosd(cosH) : acosd(cosH)
        h /= 15
        let universal = h + ra - (0.06571 * t) - 6.622
        return universal - lngHour
    }

    private static func dateFromUniversalHours(_ hours: Double, year: Int, month: Int, day: Int) -> Date? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? utc.timeZone
        guard let midnight = utc.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return midnight.addingTimeInterval(hours * 3600)
    }

    private static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? utc.timeZone
        guard let start = utc.date(from: DateComponents(year: year, month: 1, day: 1)),
              let date = utc.date(from: DateComponents(year: year, month: month, day: day))
        else { return day }
        return (utc.dateComponents([.day], from: start, to: date).day ?? 0) + 1
    }

    private static func sind(_ degrees: Double) -> Double { sin(degrees * .pi / 180) }
    private static func cosd(_ degrees: Double) -> Double { cos(degrees * .pi / 180) }
    private static func tand(_ degrees: Double) -> Double { tan(degrees * .pi / 180) }
    private static func atand(_ value: Double) -> Double { atan(value) * 180 / .pi }
    private static func asind(_ value: Double) -> Double { asin(min(1, max(-1, value))) * 180 / .pi }
    private static func acosd(_ value: Double) -> Double { acos(min(1, max(-1, value))) * 180 / .pi }

    private static func wrap360(_ value: Double) -> Double {
        var wrapped = value.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        return wrapped
    }
}
