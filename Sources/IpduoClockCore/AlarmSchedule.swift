import Foundation

public enum AlarmSound: Codable, Equatable {
    case tone
    case song(id: String, title: String, artist: String)
    case episode(id: String, title: String, streamURL: String)

    public var menuTitle: String {
        switch self {
        case .tone: return "Tone"
        case .song(_, let title, _): return title
        case .episode(_, let title, _): return title
        }
    }
}

public struct Alarm: Identifiable, Codable, Equatable {
    public var id: UUID
    public var hour: Int
    public var minute: Int
    public var repeatWeekdays: [Int]
    public var label: String
    public var isEnabled: Bool
    public var snoozeMinutes: Int
    public var sound: AlarmSound

    public init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        repeatWeekdays: [Int] = [],
        label: String = "Alarm",
        isEnabled: Bool = true,
        snoozeMinutes: Int = 9,
        sound: AlarmSound = .tone
    ) {
        self.id = id
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
        self.repeatWeekdays = Array(Set(repeatWeekdays.filter { (1...7).contains($0) })).sorted()
        self.label = label
        self.isEnabled = isEnabled
        self.snoozeMinutes = max(1, snoozeMinutes)
        self.sound = sound
    }

    public var repeatSet: Set<Int> { Set(repeatWeekdays) }

    public func nextFire(from date: Date, calendar: Calendar, respectEnabled: Bool = true) -> Date? {
        if respectEnabled && !isEnabled { return nil }
        return AlarmScheduling.nextFireDate(
            hour: hour,
            minute: minute,
            repeatDays: repeatSet,
            from: date,
            calendar: calendar
        )
    }
}

public struct AlarmTrigger: Equatable {
    public var dateComponents: DateComponents
    public var repeats: Bool

    public init(dateComponents: DateComponents, repeats: Bool) {
        self.dateComponents = dateComponents
        self.repeats = repeats
    }
}

public enum AlarmScheduling {
    /// The next moment this alarm should fire. One-shot alarms roll to tomorrow once today's time has passed.
    /// Repeating alarms pick the next listed weekday. `repeatDays` uses `Calendar` weekday numbers (1 = Sunday).
    public static func nextFireDate(
        hour: Int,
        minute: Int,
        repeatDays: Set<Int>,
        from date: Date,
        calendar: Calendar
    ) -> Date? {
        let hour = min(23, max(0, hour))
        let minute = min(59, max(0, minute))
        let days = Set(repeatDays.filter { (1...7).contains($0) })
        if days.isEmpty {
            return nextOneShot(hour: hour, minute: minute, from: date, calendar: calendar)
        }
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { continue }
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = hour
            parts.minute = minute
            parts.second = 0
            guard let candidate = calendar.date(from: parts), candidate > date else { continue }
            let weekday = calendar.component(.weekday, from: candidate)
            if days.contains(weekday) { return candidate }
        }
        return nil
    }

    /// Notification triggers. Repeating alarms emit one weekly trigger per selected weekday.
    /// A one-shot alarm emits a single non-repeating date.
    public static func triggers(
        hour: Int,
        minute: Int,
        repeatDays: Set<Int>,
        from date: Date,
        calendar: Calendar
    ) -> [AlarmTrigger] {
        let hour = min(23, max(0, hour))
        let minute = min(59, max(0, minute))
        let days = Set(repeatDays.filter { (1...7).contains($0) })
        if days.isEmpty {
            guard let next = nextOneShot(hour: hour, minute: minute, from: date, calendar: calendar) else { return [] }
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next)
            parts.second = 0
            parts.calendar = calendar
            parts.timeZone = calendar.timeZone
            return [AlarmTrigger(dateComponents: parts, repeats: false)]
        }
        return days.sorted().map { weekday in
            var parts = DateComponents()
            parts.calendar = calendar
            parts.timeZone = calendar.timeZone
            parts.weekday = weekday
            parts.hour = hour
            parts.minute = minute
            return AlarmTrigger(dateComponents: parts, repeats: true)
        }
    }

    public static func snoozeDate(from date: Date, minutes: Int) -> Date {
        date.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
    }

    public static func repeatSummary(weekdays: Set<Int>, symbols: [String]) -> String {
        let days = weekdays.filter { (1...7).contains($0) }.sorted()
        if days.isEmpty { return "Once" }
        if days.count == 7 { return "Every day" }
        let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]
        let weekend: Set<Int> = [1, 7]
        if days == weekdaysOnly.sorted() || Set(days) == weekdaysOnly { return "Weekdays" }
        if Set(days) == weekend { return "Weekends" }
        let names = days.compactMap { index -> String? in
            let symbolIndex = index - 1
            guard symbols.indices.contains(symbolIndex) else { return nil }
            return symbols[symbolIndex]
        }
        return names.joined(separator: " ")
    }

    private static func nextOneShot(hour: Int, minute: Int, from date: Date, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        guard var candidate = calendar.date(from: parts) else { return nil }
        if candidate <= date {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = tomorrow
        }
        return candidate
    }
}
