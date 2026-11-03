import IpduoClockCore
import SwiftUI

enum ListenSection: String, CaseIterable, Identifiable {
    case music
    case podcasts
    var id: String { rawValue }
    var title: String { self == .music ? "Music" : "Podcasts" }
}

struct ListenScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter
    @EnvironmentObject private var podcasts: PodcastClient

    var body: some View {
        NavigationSplitView {
            ListenLibrary()
        } detail: {
            NowPlayingView()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct ListenLibrary: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter
    @EnvironmentObject private var podcasts: PodcastClient
    @State private var section: ListenSection = {
        switch ScreenshotSession.screen {
        case "listen-podcasts": return .podcasts
        default: return .music
        }
    }()
    @State private var query = ScreenshotSession.screen == "listen-podcasts" ? ScreenshotSession.podcastQuery : ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library", selection: $section) {
                ForEach(ListenSection.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if let message = section == .music ? playback.message : podcasts.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            Group {
                switch section {
                case .music:
                    MusicBrowser(query: query)
                case .podcasts:
                    PodcastBrowser(query: query)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(StageBackground(tint: model.accentColor))
        .navigationTitle("Listen")
        .searchable(text: $query, prompt: section == .music ? "Search Apple Music" : "Search podcasts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    model.settingsPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .duoPriorityLow()
        }
        .task(id: query + section.rawValue) {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            if section == .music {
                await playback.searchMusic(query)
            } else {
                await podcasts.search(query)
            }
        }
        .task {
            guard model.screenshotScreen == nil else { return }
            await playback.requestMusicAccess()
        }
        .onChange(of: model.screenshotSearchTerm) { _, term in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != query else { return }
            query = trimmed
            section = .podcasts
        }
    }
}

private struct MusicBrowser: View {
    var query: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter

    private var songs: [SongSnapshot] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? playback.library : playback.musicResults
    }

    var body: some View {
        if playback.authorization != .authorized {
            ContentUnavailableView {
                Label("Apple Music", systemImage: "music.note")
            } description: {
                Text("Allow Apple Music to play songs from your library and the catalog. Ipduo Clock needs the MusicKit capability on its App ID.")
            } actions: {
                Button {
                    Task { await playback.requestMusicAccess() }
                } label: {
                    Label("Allow Apple Music", systemImage: "music.note")
                }
                .buttonStyle(.borderedProminent)
            }
        } else if songs.isEmpty {
            ContentUnavailableView(
                "No Songs",
                systemImage: "music.note.list",
                description: Text(query.isEmpty ? "Songs from your library show up here." : "Try another search.")
            )
        } else {
            EvenColumnGrid(items: songs, minimumColumnWidth: 160) { song in
                Button {
                    Haptics.tap(enabled: model.hapticsEnabled)
                    Task { await playback.play(snapshot: song) }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ArtworkView(url: song.artwork, symbol: "music.note")
                            .aspectRatio(1, contentMode: .fit)
                        Text(song.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(song.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PodcastBrowser: View {
    var query: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var podcasts: PodcastClient

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if searching {
                Section("Results") {
                    ForEach(podcasts.results) { show in
                        ShowRow(show: show)
                    }
                }
            }
            Section("Subscribed") {
                if model.subscriptions.isEmpty {
                    Text("Search the iTunes directory and subscribe. Episodes stream, resume, and can be downloaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.subscriptions) { show in
                    NavigationLink {
                        EpisodeList(show: show)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(show.title)
                            Text(show.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { model.subscriptions[$0].id }
                    ids.forEach(model.unsubscribe)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct ShowRow: View {
    var show: PodcastDirectoryEntry
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: show.artworkURL, symbol: "dot.radiowaves.up.forward")
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(show.collectionName).lineLimit(1)
                Text(show.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                model.subscribe(show)
                Haptics.success(enabled: model.hapticsEnabled)
            } label: {
                Label(model.isSubscribed(show.collectionId) ? "Subscribed" : "Subscribe", systemImage: model.isSubscribed(show.collectionId) ? "checkmark" : "plus")
            }
            .disabled(show.feed == nil || model.isSubscribed(show.collectionId))
        }
    }
}

private struct EpisodeList: View {
    var show: PodcastSubscription
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter
    @EnvironmentObject private var podcasts: PodcastClient

    private var episodes: [RSSEpisode] {
        podcasts.episodes[show.id] ?? []
    }

    var body: some View {
        List(episodes) { episode in
            VStack(alignment: .leading, spacing: 8) {
                Text(episode.title).font(.body.weight(.semibold))
                HStack(spacing: 8) {
                    if let duration = episode.duration {
                        Text(CountdownFormat.clock(duration))
                    }
                    if let published = episode.published {
                        Text(published.formatted(date: .abbreviated, time: .omitted))
                    }
                    if model.localFile(for: episode.id) != nil {
                        Label("Downloaded", systemImage: "arrow.down.circle.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let fraction = model.resumeBook.fraction(id: episode.id, duration: episode.duration) {
                    ProgressView(value: fraction)
                        .tint(model.accentColor)
                }
                HStack {
                    Button {
                        Task { await play(episode) }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    Button {
                        Task { await podcasts.download(episode, model: model) }
                    } label: {
                        Label(model.localFile(for: episode.id) == nil ? "Download" : "Downloaded", systemImage: "arrow.down.circle")
                    }
                    .disabled(model.localFile(for: episode.id) != nil)
                    if model.localFile(for: episode.id) != nil {
                        Button(role: .destructive) {
                            podcasts.removeDownload(episode.id, model: model)
                        } label: {
                            Label("Remove Download", systemImage: "trash")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if podcasts.loading && episodes.isEmpty {
                ProgressView("Loading episodes")
            }
        }
        .task {
            await podcasts.load(show, model: model)
        }
    }

    private func play(_ episode: RSSEpisode) async {
        let resume = model.resumeBook.position(for: episode.id)
        await playback.playEpisode(
            episode,
            show: show.title,
            artwork: show.artworkURL,
            resume: resume,
            localURL: model.localFile(for: episode.id)
        )
        model.nowPlayingPresented = true
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter
    @State private var scrub = 0.0
    @State private var scrubbing = false

    var body: some View {
        GeometryReader { proxy in
            let art = min(proxy.size.width, proxy.size.height) * 0.55
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(model.accentColor.opacity(0.35))
                            .frame(width: art * 1.15, height: art * 1.15)
                            .blur(radius: art * 0.18)
                        ArtworkView(url: playback.artworkURL, symbol: playback.source == .idle ? "moon.stars" : "music.note")
                            .frame(width: art, height: art)
                            .clipShape(RoundedRectangle(cornerRadius: art * 0.08, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                    }
                    VStack(spacing: 4) {
                        Text(playback.title)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(playback.subtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal)
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { scrubbing ? scrub : playback.currentTime },
                                set: { scrub = $0 }
                            ),
                            in: 0...max(playback.duration, 1)
                        ) { editing in
                            scrubbing = editing
                            if !editing {
                                playback.seek(to: scrub)
                            }
                        }
                        .tint(model.accentColor)
                        .disabled(playback.source == .idle || playback.duration <= 0)
                        HStack {
                            Text(CountdownFormat.clock(scrubbing ? scrub : playback.currentTime))
                            Spacer(minLength: 8)
                            Text(playback.duration > 0 ? CountdownFormat.clock(playback.duration) : "––")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    HStack(spacing: 18) {
                        skipButton("Back 30 Seconds", systemImage: "gobackward.30", delta: -30)
                        skipButton("Back 15 Seconds", systemImage: "gobackward.15", delta: -15)
                        Button {
                            Haptics.tap(enabled: model.hapticsEnabled)
                            playback.toggle()
                        } label: {
                            Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: min(proxy.size.width, 480) * 0.16))
                                .foregroundStyle(model.accentColor)
                        }
                        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                        .disabled(playback.source == .idle)
                        skipButton("Forward 15 Seconds", systemImage: "goforward.15", delta: 15)
                        skipButton("Forward 30 Seconds", systemImage: "goforward.30", delta: 30)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PlaybackRate.presets, id: \.self) { preset in
                                Button {
                                    playback.setRate(preset)
                                    model.playbackRate = preset
                                    model.touch()
                                    Haptics.selection(enabled: model.hapticsEnabled)
                                } label: {
                                    Text(PlaybackRate.label(preset))
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                                .tint(abs(playback.rate - preset) < 0.01 ? model.accentColor : .secondary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    if let remaining = playback.sleepRemaining, playback.sleep != nil {
                        Text("Sleep timer \(CountdownFormat.clock(remaining))")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if playback.source == .idle {
                        Text("Choose a song or episode. Playback continues on the Lock Screen, and a sleep timer can fade a podcast out.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .background(StageBackground(tint: model.accentColor))
        .screenshotMarker()
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("15 Minutes") { playback.startSleep(minutes: 15) }
                    Button("30 Minutes") { playback.startSleep(minutes: 30) }
                    Button("45 Minutes") { playback.startSleep(minutes: 45) }
                    Button("60 Minutes") { playback.startSleep(minutes: 60) }
                    Button("End of Episode") { playback.startSleepUntilEnd() }
                    if playback.sleep != nil {
                        Button("Turn Off Sleep Timer", role: .destructive) { playback.cancelSleep() }
                    }
                } label: {
                    Label("Sleep Timer", systemImage: playback.sleep == nil ? "moon.zzz" : "moon.zzz.fill")
                }
            }
            .duoPriorityHigh()
        }
    }

    private func skipButton(_ title: String, systemImage: String, delta: TimeInterval) -> some View {
        Button {
            playback.skip(by: delta)
            Haptics.selection(enabled: model.hapticsEnabled)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3)
        }
        .accessibilityLabel(title)
        .disabled(playback.source == .idle)
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var playback: PlaybackCenter

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.nowPlayingPresented = true
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: playback.artworkURL, symbol: "music.note")
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playback.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(playback.sleepRemaining == nil ? playback.subtitle : "Sleep \(CountdownFormat.clock(playback.sleepRemaining ?? 0))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button {
                playback.toggle()
                Haptics.tap(enabled: model.hapticsEnabled)
            } label: {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottom) {
            let fraction = playback.duration > 0 ? min(1, playback.currentTime / playback.duration) : 0
            Capsule()
                .fill(model.accentColor)
                .frame(height: 2)
                .scaleEffect(x: max(fraction, 0.001), y: 1, anchor: .leading)
                .padding(.horizontal, 14)
                .opacity(fraction > 0 ? 1 : 0)
        }
    }
}

struct ArtworkView: View {
    var url: URL?
    var symbol: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: symbol)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
