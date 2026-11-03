import IpduoClockCore
import SwiftUI

struct AlarmsScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var editor: AlarmDraft?

    var body: some View {
        NavigationSplitView {
            Group {
                if model.alarms.isEmpty {
                    ContentUnavailableView {
                        Label("No Alarms", systemImage: "alarm")
                    } description: {
                        Text("Add an alarm with a tone, a song, or a podcast episode.")
                    } actions: {
                        Button {
                            editor = AlarmDraft(alarm: nil)
                        } label: {
                            Label("Add Alarm", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(selection: $model.selectedAlarmID) {
                        ForEach(model.alarms) { alarm in
                            AlarmRow(alarm: alarm)
                                .tag(alarm.id)
                        }
                        .onDelete(perform: model.deleteAlarms)
                    }
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = AlarmDraft(alarm: nil)
                    } label: {
                        Label("Add Alarm", systemImage: "plus")
                    }
                }
                .duoPriorityHigh()
                ToolbarItem(placement: .automatic) {
                    Button {
                        model.settingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .duoPriorityLow()
            }
        } detail: {
            if let id = model.selectedAlarmID, let alarm = model.alarms.first(where: { $0.id == id }) {
                AlarmPreview(alarm: alarm) {
                    editor = AlarmDraft(alarm: alarm)
                }
            } else {
                ContentUnavailableView(
                    "No Alarm Selected",
                    systemImage: "alarm",
                    description: Text("Choose an alarm, or add one. The same alarm is waiting here when the phone opens.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if model.presentAddAlarm {
                editor = AlarmDraft(alarm: nil)
            }
        }
        .onChange(of: model.presentAddAlarm) { _, presented in
            if presented {
                editor = AlarmDraft(alarm: nil)
            }
        }
        .sheet(item: $editor) { draft in
            AlarmEditorSheet(draft: draft) { alarm in
                model.upsertAlarm(alarm)
                Haptics.success(enabled: model.hapticsEnabled)
            }
        }
    }
}

private struct AlarmRow: View {
    var alarm: Alarm
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ClockFormat.hourMinute(hour: alarm.hour, minute: alarm.minute, use24Hour: model.use24Hour))
                    .font(.system(.title, design: .rounded, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(alarm.isEnabled ? Color.primary : Color.secondary)
                Text(rowSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle(alarm.isEnabled ? "Alarm On" : "Alarm Off", isOn: Binding(
                get: { alarm.isEnabled },
                set: { enabled in
                    Haptics.tap(enabled: model.hapticsEnabled)
                    model.setAlarm(alarm.id, enabled: enabled)
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var rowSubtitle: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let days = AlarmScheduling.repeatSummary(weekdays: alarm.repeatSet, symbols: symbols)
        let label = alarm.label.isEmpty ? "Alarm" : alarm.label
        return "\(label) · \(days) · \(alarm.sound.menuTitle)"
    }
}

private struct AlarmPreview: View {
    var alarm: Alarm
    var edit: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            StageBackground(tint: model.accentColor)
            VStack(spacing: 16) {
                Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                    .font(.title.weight(.semibold))
                Text(ClockFormat.hourMinute(hour: alarm.hour, minute: alarm.minute, use24Hour: model.use24Hour))
                    .font(.system(size: 280, weight: .thin, design: .rounded))
                    .minimumScaleFactor(0.05)
                    .lineLimit(1)
                    .monospacedDigit()
                    .padding(.horizontal)
                Text(AlarmScheduling.repeatSummary(weekdays: alarm.repeatSet, symbols: Calendar.current.shortWeekdaySymbols))
                    .foregroundStyle(.secondary)
                Label(alarm.sound.menuTitle, systemImage: symbol)
                    .foregroundStyle(model.accentColor)
                if let next = alarm.nextFire(from: Date(), calendar: .current) {
                    Text("Next, \(next.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !alarm.isEnabled {
                    Text("Off")
                        .foregroundStyle(.secondary)
                }
                Button(action: edit) {
                    Label("Edit Alarm", systemImage: "pencil")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Alarm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var symbol: String {
        switch alarm.sound {
        case .tone: return "bell"
        case .song: return "music.note"
        case .episode: return "dot.radiowaves.up.forward"
        }
    }
}

private struct AlarmEpisodeChoice: Identifiable {
    var id: String
    var showTitle: String
    var episode: CachedEpisode
}

struct AlarmDraft: Identifiable {
    var id = UUID()
    var alarm: Alarm
    var isNew: Bool

    init(alarm existing: Alarm?) {
        if let existing {
            alarm = existing
            isNew = false
        } else {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
            alarm = Alarm(hour: parts.hour ?? 7, minute: parts.minute ?? 0, label: "Alarm")
            isNew = true
        }
    }
}

struct AlarmEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter
    @Environment(\.dismiss) private var dismiss
    @State var draft: AlarmDraft
    var onSave: (Alarm) -> Void
    @State private var time = Date()
    @State private var kind: SoundKind = .tone
    @State private var songQuery = ""

    enum SoundKind: String, CaseIterable, Identifiable {
        case tone = "Tone"
        case song = "Song"
        case episode = "Podcast"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                TextField("Label", text: $draft.alarm.label)
                Section("Repeat") {
                    HStack(spacing: 6) {
                        ForEach(orderedWeekdays, id: \.self) { day in
                            let selected = draft.alarm.repeatSet.contains(day)
                            Button {
                                toggle(day)
                            } label: {
                                Text(shortSymbol(day))
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(selected ? model.accentColor : .secondary)
                            .accessibilityLabel(longSymbol(day))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                Stepper(value: $draft.alarm.snoozeMinutes, in: 1...30) {
                    Text("Snooze \(draft.alarm.snoozeMinutes) min")
                }
                Picker("Sound", selection: $kind) {
                    ForEach(SoundKind.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                soundPicker
            }
            .navigationTitle(draft.isNew ? "Add Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                .duoPriorityHigh()
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        commitTime()
                        onSave(draft.alarm)
                        dismiss()
                    } label: {
                        Label("Save Alarm", systemImage: "checkmark")
                    }
                }
                .duoPriorityHigh()
            }
            .onAppear {
                var calendar = Calendar.current
                time = calendar.date(from: DateComponents(hour: draft.alarm.hour, minute: draft.alarm.minute)) ?? Date()
                switch draft.alarm.sound {
                case .tone: kind = .tone
                case .song: kind = .song
                case .episode: kind = .episode
                }
                if playback.library.isEmpty && playback.authorization == .authorized {
                    Task { await playback.loadLibrary() }
                }
            }
            .onChange(of: kind) { _, newValue in
                if newValue == .tone {
                    draft.alarm.sound = .tone
                }
            }
            .screenshotMarker()
        }
    }

    @ViewBuilder
    private var soundPicker: some View {
        switch kind {
        case .tone:
            Text("The alarm uses a standard notification tone. Open the alarm to keep it ringing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .song:
            if playback.authorization != .authorized {
                Button {
                    Task { await playback.requestMusicAccess() }
                } label: {
                    Label("Allow Apple Music", systemImage: "music.note")
                }
            } else {
                TextField("Search songs", text: $songQuery)
                    .onSubmit { Task { await playback.searchMusic(songQuery) } }
                let songs = songQuery.isEmpty ? playback.library : playback.musicResults
                if songs.isEmpty {
                    Text("Your library appears here after Apple Music is allowed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(songs) { song in
                    Button {
                        draft.alarm.sound = .song(id: song.id, title: song.title, artist: song.artist)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(song.title)
                                Text(song.artist).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if case .song(let id, _, _) = draft.alarm.sound, id == song.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(model.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        case .episode:
            let cached = alarmEpisodeChoices
            if cached.isEmpty {
                Text("Subscribe to a podcast in Listen and open it once. Its episodes can then wake you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(cached) { choice in
                Button {
                    draft.alarm.sound = .episode(
                        id: choice.episode.id,
                        title: choice.episode.title,
                        streamURL: choice.episode.streamURL
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(choice.episode.title).lineLimit(1)
                            Text(choice.showTitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if case .episode(let id, _, _) = draft.alarm.sound, id == choice.episode.id {
                            Image(systemName: "checkmark").foregroundStyle(model.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { index in ((first - 1 + index) % 7) + 1 }
    }

    private func shortSymbol(_ day: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        guard symbols.indices.contains(day - 1) else { return "" }
        return symbols[day - 1]
    }

    private func longSymbol(_ day: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        guard symbols.indices.contains(day - 1) else { return "Day" }
        return symbols[day - 1]
    }

    private func toggle(_ day: Int) {
        var days = draft.alarm.repeatWeekdays
        if let index = days.firstIndex(of: day) {
            days.remove(at: index)
        } else {
            days.append(day)
        }
        draft.alarm.repeatWeekdays = days.sorted()
        Haptics.selection(enabled: model.hapticsEnabled)
    }

    private var alarmEpisodeChoices: [AlarmEpisodeChoice] {
        model.subscriptions.flatMap { show in
            (show.cachedEpisodes ?? []).map {
                AlarmEpisodeChoice(id: "\(show.id)-\($0.id)", showTitle: show.title, episode: $0)
            }
        }
    }

    private func commitTime() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        draft.alarm.hour = parts.hour ?? draft.alarm.hour
        draft.alarm.minute = parts.minute ?? draft.alarm.minute
    }
}

struct RingingView: View {
    var alarm: Alarm
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter

    var body: some View {
        ZStack {
            StageBackground(tint: model.accentColor)
            VStack(spacing: 22) {
                Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(ClockFormat.hourMinute(hour: alarm.hour, minute: alarm.minute, use24Hour: model.use24Hour))
                    .font(.system(size: 360, weight: .thin, design: .rounded))
                    .minimumScaleFactor(0.05)
                    .lineLimit(1)
                    .monospacedDigit()
                    .padding(.horizontal)
                if playback.source != .idle {
                    Text(playback.title)
                        .font(.headline)
                        .lineLimit(1)
                        .padding(.horizontal)
                }
                HStack(spacing: 16) {
                    Button {
                        model.snoozeRinging(playback: playback)
                    } label: {
                        Label("Snooze", systemImage: "zzz")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        model.stopRinging(playback: playback)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
}
