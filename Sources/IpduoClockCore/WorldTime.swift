import Foundation

public struct WorldCity: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var region: String
    public var timeZoneIdentifier: String
    public var latitude: Double
    public var longitude: Double

    public init(
        name: String,
        region: String,
        timeZoneIdentifier: String,
        latitude: Double,
        longitude: Double
    ) {
        self.id = "\(name)|\(timeZoneIdentifier)"
        self.name = name
        self.region = region
        self.timeZoneIdentifier = timeZoneIdentifier
        self.latitude = latitude
        self.longitude = longitude
    }

    public var timeZone: TimeZone? {
        TimeZone(identifier: timeZoneIdentifier)
    }
}

public struct ClockOffset: Equatable {
    public var dayShift: Int
    public var seconds: Int

    public init(dayShift: Int, seconds: Int) {
        self.dayShift = dayShift
        self.seconds = seconds
    }

    /// "+5HRS", "−3HRS", or "+5:30" for offsets that are not a whole hour.
    public var hourMinuteLabel: String {
        if seconds == 0 { return "Same time" }
        let sign = seconds > 0 ? "+" : "−"
        let absolute = abs(seconds)
        let hours = absolute / 3600
        let minutes = (absolute % 3600) / 60
        if minutes == 0 {
            return "\(sign)\(hours)HRS"
        }
        return String(format: "%@%d:%02d", sign, hours, minutes)
    }

    public var dayLabel: String {
        switch dayShift {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case let value where value > 1: return "In \(value) days"
        default: return "\(abs(dayShift)) days ago"
        }
    }

    public var summary: String {
        if seconds == 0 && dayShift == 0 { return "Today, same time" }
        return "\(dayLabel), \(hourMinuteLabel)"
    }
}

public enum WorldTime {
    public static func offset(from local: TimeZone, to city: TimeZone, at date: Date) -> ClockOffset {
        let localDay = civilDay(date, timeZone: local)
        let cityDay = civilDay(date, timeZone: city)
        let dayShift = dayDelta(from: localDay, to: cityDay)
        let seconds = city.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        return ClockOffset(dayShift: dayShift, seconds: seconds)
    }

    public static func isDaylight(
        at date: Date,
        timeZone: TimeZone,
        latitude: Double?,
        longitude: Double?
    ) -> Bool {
        if let latitude, let longitude,
           let daylight = Solar.daylight(latitude: latitude, longitude: longitude, on: date, timeZone: timeZone) {
            return date >= daylight.sunrise && date < daylight.sunset
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return (7..<19).contains(hour)
    }

    public static func match(timeZone: TimeZone, in catalog: [WorldCity] = CityCatalog.all) -> WorldCity? {
        catalog.first { $0.timeZoneIdentifier == timeZone.identifier }
    }

    private struct CivilDay: Equatable {
        var year: Int
        var month: Int
        var day: Int
    }

    private static func civilDay(_ date: Date, timeZone: TimeZone) -> CivilDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CivilDay(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    private static func dayDelta(from start: CivilDay, to end: CivilDay) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? utc.timeZone
        guard let a = utc.date(from: DateComponents(year: start.year, month: start.month, day: start.day)),
              let b = utc.date(from: DateComponents(year: end.year, month: end.month, day: end.day))
        else { return 0 }
        return utc.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

public enum CityCatalog {
    public static let all: [WorldCity] = [
        WorldCity(name: "Honolulu", region: "United States", timeZoneIdentifier: "Pacific/Honolulu", latitude: 21.3069, longitude: -157.8583),
        WorldCity(name: "Anchorage", region: "United States", timeZoneIdentifier: "America/Anchorage", latitude: 61.2181, longitude: -149.9003),
        WorldCity(name: "Los Angeles", region: "United States", timeZoneIdentifier: "America/Los_Angeles", latitude: 34.0522, longitude: -118.2437),
        WorldCity(name: "Denver", region: "United States", timeZoneIdentifier: "America/Denver", latitude: 39.7392, longitude: -104.9903),
        WorldCity(name: "Chicago", region: "United States", timeZoneIdentifier: "America/Chicago", latitude: 41.8781, longitude: -87.6298),
        WorldCity(name: "New York", region: "United States", timeZoneIdentifier: "America/New_York", latitude: 40.7128, longitude: -74.0060),
        WorldCity(name: "Toronto", region: "Canada", timeZoneIdentifier: "America/Toronto", latitude: 43.6532, longitude: -79.3832),
        WorldCity(name: "Mexico City", region: "Mexico", timeZoneIdentifier: "America/Mexico_City", latitude: 19.4326, longitude: -99.1332),
        WorldCity(name: "São Paulo", region: "Brazil", timeZoneIdentifier: "America/Sao_Paulo", latitude: -23.5558, longitude: -46.6396),
        WorldCity(name: "Buenos Aires", region: "Argentina", timeZoneIdentifier: "America/Argentina/Buenos_Aires", latitude: -34.6037, longitude: -58.3816),
        WorldCity(name: "Reykjavík", region: "Iceland", timeZoneIdentifier: "Atlantic/Reykjavik", latitude: 64.1466, longitude: -21.9426),
        WorldCity(name: "London", region: "United Kingdom", timeZoneIdentifier: "Europe/London", latitude: 51.5072, longitude: -0.1276),
        WorldCity(name: "Lisbon", region: "Portugal", timeZoneIdentifier: "Europe/Lisbon", latitude: 38.7223, longitude: -9.1393),
        WorldCity(name: "Paris", region: "France", timeZoneIdentifier: "Europe/Paris", latitude: 48.8566, longitude: 2.3522),
        WorldCity(name: "Berlin", region: "Germany", timeZoneIdentifier: "Europe/Berlin", latitude: 52.5200, longitude: 13.4050),
        WorldCity(name: "Rome", region: "Italy", timeZoneIdentifier: "Europe/Rome", latitude: 41.9028, longitude: 12.4964),
        WorldCity(name: "Madrid", region: "Spain", timeZoneIdentifier: "Europe/Madrid", latitude: 40.4168, longitude: -3.7038),
        WorldCity(name: "Amsterdam", region: "Netherlands", timeZoneIdentifier: "Europe/Amsterdam", latitude: 52.3676, longitude: 4.9041),
        WorldCity(name: "Stockholm", region: "Sweden", timeZoneIdentifier: "Europe/Stockholm", latitude: 59.3293, longitude: 18.0686),
        WorldCity(name: "Athens", region: "Greece", timeZoneIdentifier: "Europe/Athens", latitude: 37.9838, longitude: 23.7275),
        WorldCity(name: "Istanbul", region: "Türkiye", timeZoneIdentifier: "Europe/Istanbul", latitude: 41.0082, longitude: 28.9784),
        WorldCity(name: "Cairo", region: "Egypt", timeZoneIdentifier: "Africa/Cairo", latitude: 30.0444, longitude: 31.2357),
        WorldCity(name: "Johannesburg", region: "South Africa", timeZoneIdentifier: "Africa/Johannesburg", latitude: -26.2041, longitude: 28.0473),
        WorldCity(name: "Nairobi", region: "Kenya", timeZoneIdentifier: "Africa/Nairobi", latitude: -1.2921, longitude: 36.8219),
        WorldCity(name: "Moscow", region: "Russia", timeZoneIdentifier: "Europe/Moscow", latitude: 55.7558, longitude: 37.6173),
        WorldCity(name: "Dubai", region: "United Arab Emirates", timeZoneIdentifier: "Asia/Dubai", latitude: 25.2048, longitude: 55.2708),
        WorldCity(name: "Mumbai", region: "India", timeZoneIdentifier: "Asia/Kolkata", latitude: 19.0760, longitude: 72.8777),
        WorldCity(name: "Delhi", region: "India", timeZoneIdentifier: "Asia/Kolkata", latitude: 28.6139, longitude: 77.2090),
        WorldCity(name: "Bangkok", region: "Thailand", timeZoneIdentifier: "Asia/Bangkok", latitude: 13.7563, longitude: 100.5018),
        WorldCity(name: "Singapore", region: "Singapore", timeZoneIdentifier: "Asia/Singapore", latitude: 1.3521, longitude: 103.8198),
        WorldCity(name: "Hong Kong", region: "China", timeZoneIdentifier: "Asia/Hong_Kong", latitude: 22.3193, longitude: 114.1694),
        WorldCity(name: "Shanghai", region: "China", timeZoneIdentifier: "Asia/Shanghai", latitude: 31.2304, longitude: 121.4737),
        WorldCity(name: "Taipei", region: "Taiwan", timeZoneIdentifier: "Asia/Taipei", latitude: 25.0330, longitude: 121.5654),
        WorldCity(name: "Seoul", region: "South Korea", timeZoneIdentifier: "Asia/Seoul", latitude: 37.5665, longitude: 126.9780),
        WorldCity(name: "Tokyo", region: "Japan", timeZoneIdentifier: "Asia/Tokyo", latitude: 35.6762, longitude: 139.6503),
        WorldCity(name: "Sydney", region: "Australia", timeZoneIdentifier: "Australia/Sydney", latitude: -33.8688, longitude: 151.2093),
        WorldCity(name: "Melbourne", region: "Australia", timeZoneIdentifier: "Australia/Melbourne", latitude: -37.8136, longitude: 144.9631),
        WorldCity(name: "Auckland", region: "New Zealand", timeZoneIdentifier: "Pacific/Auckland", latitude: -36.8509, longitude: 174.7645)
    ]

    public static let starterIDs: [String] = [
        "New York|America/New_York",
        "London|Europe/London",
        "Tokyo|Asia/Tokyo",
        "Paris|Europe/Paris"
    ]

    public static func city(id: String) -> WorldCity? {
        all.first { $0.id == id }
    }
}
