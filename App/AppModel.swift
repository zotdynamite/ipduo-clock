import Combine
import Foundation
import IpduoClockCore
import UserNotifications

enum AppTab: String, Codable, CaseIterable, Identifiable {
    case clock
    case alarms
    case timers
    case world
    case listen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .alarms: return "Alarms"
        case .timers: return "Timers"
        case .world: return "World"
        case .listen: return "Listen"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .alarms: return "alarm"
        case .timers: return "timer"
        case .world: return "globe"
        case .listen: return "music.note"
        }
    }
}

enum TimerSegment: String, Codable {
    case timer
    case stopwatch
}

struct CachedEpisode: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var streamURL: String
}

struct PodcastSubscription: Identifiable, Codable, Equatable {
    var id: Int
    var title: String
    var author: String
    var feedURL: URL
    var artworkURL: URL?
    /// Recent episodes kept so an alarm can wake with one of them.
    var cachedEpisodes: [CachedEpisode]? = nil
}

@MainActor
final class AppModel: ObservableObject {
    @Published var appearance: AppearanceChoice
    @Published var accent: AccentPalette
    @Published var use24Hour: Bool
    @Published var hapticsEnabled: Bool
    @Published var showSeconds: Bool
    @Published var face: ClockFaceID
    @Published var tab: AppTab
    @Published var cityIDs: [String]
    @Published var selectedCityID: String?
    @Published var alarms: [Alarm]
    @Published var selectedAlarmID: UUID?
    @Published var timerSegment: TimerSegment
    @Published var subscriptions: [PodcastSubscription]
    @Published var resumeBook: ResumeBook
    @Published var downloads: [String: String]
    @Published var playbackRate: Float
    @Published var stopwatch = StopwatchState()
    @Published var countdown: CountdownState
    @Published var standByPresented = false
    @Published var ringingAlarm: Alarm?
    @Published var settingsPresented = false
    @Published var nowPlayingPresented = false
    /// Set by `-ipduo-screen`. Nil in normal launches.
    let screenshotScreen: String?
    @Published var screenshotReady = false
    @Published var presentAddAlarm = false
    @Published var screenshotSearchTerm = ""

    private var saveScheduled = false

    init() {
        if let screen = ScreenshotSession.screen {
            screenshotScreen = screen
            appearance = .dark
            accent = .aurora
            use24Hour = true
            hapticsEnabled = false
            showSeconds = true
            face = ScreenshotSession.face(for: screen)
            tab = ScreenshotSession.tab(for: screen)
            cityIDs = CityCatalog.starterIDs
            selectedCityID = screen == "world" ? nil : CityCatalog.starterIDs.first
            let alarm = Alarm(
                hour: 7,
                minute: 30,
                repeatWeekdays: [2, 3, 4, 5, 6],
                label: "Wake"
            )
            alarms = [alarm]
            selectedAlarmID = screen == "regular-alarms" ? alarm.id : nil
            timerSegment = screen == "stopwatch" ? .stopwatch : .timer
            subscriptions = []
            resumeBook = ResumeBook(positions: [:])
            downloads = [:]
            playbackRate = 1
            countdown = Self.screenshotCountdown(for: screen)
            stopwatch = Self.screenshotStopwatch(for: screen)
            settingsPresented = screen == "settings"
            standByPresented = screen == "standby"
            presentAddAlarm = screen == "add-alarm"
            screenshotSearchTerm = screen == "listen-podcasts" ? ScreenshotSession.podcastQuery : ""
            return
        }

        screenshotScreen = nil
        let stored = PersistedClock.load()
        appearance = stored.appearance
        accent = stored.accent
        use24Hour = stored.use24Hour
        hapticsEnabled = stored.hapticsEnabled
        showSeconds = stored.showSeconds
        face = stored.face
        tab = stored.tab
        cityIDs = stored.cityIDs
        alarms = stored.alarms
        timerSegment = stored.timerSegment
        subscriptions = stored.subscriptions
        resumeBook = ResumeBook(positions: stored.resume)
        downloads = stored.downloads
        playbackRate = PlaybackRate.clamped(stored.playbackRate)
        countdown = CountdownState(duration: stored.countdownDuration)
        selectedCityID = stored.cityIDs.first
    }

    private static func screenshotCountdown(for screen: String) -> CountdownState {
        guard screen == "timer" || screen == "regular-timers" else {
            return CountdownState(duration: 5 * 60)
        }
        var countdown = CountdownState(duration: 5 * 60)
        let now = Date()
        countdown.start(at: now.addingTimeInterval(-100))
        countdown.pause(at: now)
        return countdown
    }

    private static func screenshotStopwatch(for screen: String) -> StopwatchState {
        guard screen == "stopwatch" || screen == "regular-timers" else { return StopwatchState() }
        var stopwatch = StopwatchState()
        let now = Date()
        stopwatch.start(at: now.addingTimeInterval(-150))
        stopwatch.lap(at: now.addingTimeInterval(-90))
        stopwatch.lap(at: now.addingTimeInterval(-40))
        stopwatch.pause(at: now)
        return stopwatch
    }

    var cities: [WorldCity] {
        cityIDs.compactMap(CityCatalog.city(id:))
    }

    func city(id: String) -> WorldCity? {
        CityCatalog.city(id: id)
    }

    func addCity(_ city: WorldCity) {
        guard !cityIDs.contains(city.id) else { return }
        cityIDs.append(city.id)
        selectedCityID = city.id
        touch()
    }

    func removeCities(at offsets: IndexSet) {
        cityIDs.remove(atOffsets: offsets)
        if let selectedCityID, !cityIDs.contains(selectedCityID) {
            self.selectedCityID = cityIDs.first
        }
        touch()
    }

    func upsertAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        alarms.sort { lhs, rhs in
            if lhs.hour == rhs.hour { return lhs.minute < rhs.minute }
            return lhs.hour < rhs.hour
        }
        selectedAlarmID = alarm.id
        touch()
        Task { await rescheduleAlarms() }
    }

    func deleteAlarms(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
        touch()
        Task { await rescheduleAlarms() }
    }

    func setAlarm(_ id: UUID, enabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].isEnabled = enabled
        touch()
        Task { await rescheduleAlarms() }
    }

    func nextAlarm(from date: Date = Date()) -> Alarm? {
        let calendar = Calendar.current
        return alarms
            .filter(\.isEnabled)
            .compactMap { alarm -> (Alarm, Date)? in
                guard let fire = alarm.nextFire(from: date, calendar: calendar) else { return nil }
                return (alarm, fire)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    func handleAlarm(id: String, action: String, playback: PlaybackCenter) {
        guard let uuid = UUID(uuidString: id), let alarm = alarms.first(where: { $0.id == uuid }) else { return }
        switch action {
        case AlarmNotificationAction.stop:
            playback.pause()
            ringingAlarm = nil
        case AlarmNotificationAction.snooze:
            playback.pause()
            ringingAlarm = nil
            Task { await scheduleSnooze(for: alarm) }
        default:
            ringingAlarm = alarm
            Task { await playback.playAlarm(alarm) }
        }
    }

    func stopRinging(playback: PlaybackCenter) {
        playback.pause()
        ringingAlarm = nil
    }

    func snoozeRinging(playback: PlaybackCenter) {
        guard let alarm = ringingAlarm else { return }
        playback.pause()
        ringingAlarm = nil
        Task { await scheduleSnooze(for: alarm) }
    }

    func subscribe(_ entry: PodcastDirectoryEntry) {
        guard let feed = entry.feed else { return }
        let subscription = PodcastSubscription(
            id: entry.collectionId,
            title: entry.collectionName,
            author: entry.artistName,
            feedURL: feed,
            artworkURL: entry.artworkURL
        )
        if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            subscriptions[index] = subscription
        } else {
            subscriptions.append(subscription)
        }
        touch()
    }

    func unsubscribe(_ id: Int) {
        subscriptions.removeAll { $0.id == id }
        touch()
    }

    func isSubscribed(_ id: Int) -> Bool {
        subscriptions.contains { $0.id == id }
    }

    func rememberPlayback(id: String, seconds: TimeInterval, duration: TimeInterval) {
        resumeBook.record(id: id, seconds: seconds, duration: duration > 0 ? duration : nil)
        touch()
    }

    func localFile(for episodeID: String) -> URL? {
        guard let name = downloads[episodeID] else { return nil }
        let url = Self.downloadsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func setDownload(episodeID: String, filename: String?) {
        if let filename {
            downloads[episodeID] = filename
        } else if let existing = downloads.removeValue(forKey: episodeID) {
            let url = Self.downloadsDirectory.appendingPathComponent(existing)
            try? FileManager.default.removeItem(at: url)
        }
        touch()
    }

    func touch() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            saveScheduled = false
            persist()
        }
    }

    func persist() {
        guard screenshotScreen == nil else { return }
        PersistedClock(
            appearance: appearance,
            accent: accent,
            use24Hour: use24Hour,
            hapticsEnabled: hapticsEnabled,
            showSeconds: showSeconds,
            face: face,
            tab: tab,
            cityIDs: cityIDs,
            alarms: alarms,
            timerSegment: timerSegment,
            subscriptions: subscriptions,
            resume: resumeBook.positions,
            downloads: downloads,
            playbackRate: playbackRate,
            countdownDuration: countdown.duration
        ).save()
    }

    func rescheduleAlarms() async {
        guard screenshotScreen == nil else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("ipduo-alarm-") }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        let others = pending.count - ours.count
        var budget = max(0, 60 - others)
        let calendar = Calendar.current
        let now = Date()
        for alarm in alarms where alarm.isEnabled {
            guard budget > 0 else { break }
            let triggers = AlarmScheduling.triggers(
                hour: alarm.hour,
                minute: alarm.minute,
                repeatDays: alarm.repeatSet,
                from: now,
                calendar: calendar
            )
            for (index, trigger) in triggers.enumerated() {
                guard budget > 0 else { break }
                let identifier = "ipduo-alarm-\(alarm.id.uuidString)-\(index)"
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content(for: alarm),
                    trigger: UNCalendarNotificationTrigger(dateMatching: trigger.dateComponents, repeats: trigger.repeats)
                )
                try? await center.add(request)
                budget -= 1
            }
        }
    }

    private func scheduleSnooze(for alarm: Alarm) async {
        let center = UNUserNotificationCenter.current()
        let fire = AlarmScheduling.snoozeDate(from: Date(), minutes: alarm.snoozeMinutes)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        let request = UNNotificationRequest(
            identifier: "ipduo-alarm-\(alarm.id.uuidString)-snooze",
            content: content(for: alarm),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    private func content(for alarm: Alarm) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Alarm" : alarm.label
        content.body = ClockFormat.hourMinute(hour: alarm.hour, minute: alarm.minute, use24Hour: use24Hour)
        switch alarm.sound {
        case .tone:
            content.sound = .default
        case .song(_, let title, let artist):
            content.sound = .default
            content.body = "Wake with \(title) · \(artist)"
        case .episode(_, let title, _):
            content.sound = .default
            content.body = "Wake with \(title)"
        }
        content.categoryIdentifier = AlarmNotificationAction.category
        content.userInfo = [AlarmNotificationAction.alarmID: alarm.id.uuidString]
        return content
    }

    static var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IpduoClock", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var downloadsDirectory: URL {
        let url = supportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct PersistedClock: Codable {
    var appearance: AppearanceChoice = .system
    var accent: AccentPalette = .aurora
    var use24Hour: Bool = true
    var hapticsEnabled: Bool = true
    var showSeconds: Bool = true
    var face: ClockFaceID = .analog
    var tab: AppTab = .clock
    var cityIDs: [String] = CityCatalog.starterIDs
    var alarms: [Alarm] = []
    var timerSegment: TimerSegment = .timer
    var subscriptions: [PodcastSubscription] = []
    var resume: [String: TimeInterval] = [:]
    var downloads: [String: String] = [:]
    var playbackRate: Float = 1
    var countdownDuration: TimeInterval = 5 * 60

    static func load() -> PersistedClock {
        let url = AppModel.supportDirectory.appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(PersistedClock.self, from: data)
        else {
            var fresh = PersistedClock()
            let local = TimeZone.current.identifier
            if CityCatalog.all.contains(where: { $0.timeZoneIdentifier == local }) {
                fresh.cityIDs.removeAll { id in
                    CityCatalog.city(id: id)?.timeZoneIdentifier == local
                }
            }
            if fresh.cityIDs.isEmpty {
                fresh.cityIDs = CityCatalog.starterIDs
            }
            let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
            fresh.use24Hour = template.contains("H")
            return fresh
        }
        return stored
    }

    func save() {
        let url = AppModel.supportDirectory.appendingPathComponent("state.json")
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
