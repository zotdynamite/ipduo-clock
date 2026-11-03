import AVFoundation
import Foundation
import IpduoClockCore
import MediaPlayer
import MusicKit
import SwiftUI
import UIKit

struct SongSnapshot: Identifiable, Equatable {
    var id: String
    var title: String
    var artist: String
    var artwork: URL?
    var duration: TimeInterval
}

@MainActor
final class PlaybackCenter: ObservableObject {
    enum Source: Equatable {
        case idle
        case music(id: String, title: String, artist: String, artwork: URL?)
        case episode(id: String, title: String, show: String, artwork: URL?)
    }

    @Published var source: Source = .idle
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var rate: Float = 1
    @Published var sleep: SleepFade?
    @Published var sleepRemaining: TimeInterval?
    @Published var authorization: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @Published var library: [SongSnapshot] = []
    @Published var musicResults: [SongSnapshot] = []
    @Published var message: String?
    @Published private(set) var activeEpisodeID: String?

    private let player = AVPlayer()
    private var songs: [String: Song] = [:]
    private var timeToken: Any?
    private var endObserver: NSObjectProtocol?
    private var sleepTask: Task<Void, Never>?
    private var musicPoll: Task<Void, Never>?
    private var progressHandler: ((String, TimeInterval, TimeInterval) -> Void)?
    private var remoteInstalled = false

    var showsMiniPlayer: Bool { source != .idle }

    var title: String {
        switch source {
        case .idle: return "Nothing playing"
        case .music(_, let title, _, _): return title
        case .episode(_, let title, _, _): return title
        }
    }

    var subtitle: String {
        switch source {
        case .idle: return ""
        case .music(_, _, let artist, _): return artist
        case .episode(_, _, let show, _): return show
        }
    }

    var artworkURL: URL? {
        switch source {
        case .idle: return nil
        case .music(_, _, _, let artwork): return artwork
        case .episode(_, _, _, let artwork): return artwork
        }
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        installTimeObserver()
        installEndObserver()
        installRemoteCommands()
    }

    func bindProgress(_ handler: @escaping (String, TimeInterval, TimeInterval) -> Void) {
        progressHandler = handler
    }

    func prepare(rate: Float) {
        self.rate = PlaybackRate.clamped(rate)
    }

    func requestMusicAccess() async {
        authorization = await MusicAuthorization.request()
        if authorization == .authorized {
            await loadLibrary()
        }
    }

    func loadLibrary() async {
        guard authorization == .authorized else { return }
        do {
            var request = MusicLibraryRequest<Song>()
            request.limit = 40
            let response = try await request.response()
            library = remember(Array(response.items))
        } catch {
            message = error.localizedDescription
        }
    }

    func searchMusic(_ term: String) async {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            musicResults = []
            return
        }
        guard authorization == .authorized else {
            message = "Allow Apple Music to search the catalog."
            return
        }
        do {
            var request = MusicCatalogSearchRequest(term: trimmed, types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            musicResults = remember(Array(response.songs))
        } catch {
            message = error.localizedDescription
        }
    }

    func play(snapshot: SongSnapshot) async {
        if let song = songs[snapshot.id] {
            await play(song: song)
            return
        }
        await playSong(id: snapshot.id, title: snapshot.title, artist: snapshot.artist)
    }

    func play(song: Song) async {
        pauseEpisode()
        remember([song])
        do {
            try activateSession()
            let musicPlayer = ApplicationMusicPlayer.shared
            musicPlayer.queue = ApplicationMusicPlayer.Queue(for: [song])
            try await musicPlayer.play()
            source = .music(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                artwork: song.artwork?.url(width: 600, height: 600)
            )
            duration = song.duration ?? 0
            currentTime = musicPlayer.playbackTime
            isPlaying = true
            activeEpisodeID = nil
            message = nil
            startMusicPoll()
            publishNowPlaying()
        } catch {
            message = error.localizedDescription
        }
    }

    func playSong(id: String, title: String, artist: String) async {
        if let song = songs[id] {
            await play(song: song)
            return
        }
        guard authorization == .authorized || MusicAuthorization.currentStatus == .authorized else {
            authorization = MusicAuthorization.currentStatus
            message = "Allow Apple Music to play \(title)."
            return
        }
        authorization = .authorized
        do {
            var libraryRequest = MusicLibraryRequest<Song>()
            libraryRequest.filter(matching: \.id, equalTo: MusicItemID(rawValue: id))
            let libraryResponse = try await libraryRequest.response()
            if let song = libraryResponse.items.first {
                await play(song: song)
                return
            }
            let catalog = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(rawValue: id))
            let catalogResponse = try await catalog.response()
            if let song = catalogResponse.items.first {
                await play(song: song)
                return
            }
            message = "Couldn't find \(title)."
        } catch {
            message = error.localizedDescription
        }
    }

    func playEpisode(
        _ episode: RSSEpisode,
        show: String,
        artwork: URL?,
        resume: TimeInterval,
        localURL: URL?
    ) async {
        ApplicationMusicPlayer.shared.pause()
        stopMusicPoll()
        let url = localURL ?? episode.audioURL
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        var sessionFailed = false
        do {
            try activateSession()
        } catch {
            // The player chrome should still appear if the simulator refuses the audio session.
            sessionFailed = true
            message = error.localizedDescription
        }
        if resume > 1 {
            await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
        }
        player.play()
        player.rate = rate
        source = .episode(id: episode.id, title: episode.title, show: show, artwork: artwork)
        activeEpisodeID = episode.id
        currentTime = resume
        duration = episode.duration ?? 0
        isPlaying = true
        player.volume = 1
        if !sessionFailed {
            message = nil
        }
        publishNowPlaying()
    }

    func playAlarm(_ alarm: Alarm, localEpisodeURL: URL?) async {
        switch alarm.sound {
        case .tone:
            break
        case .song(let id, let title, let artist):
            await playSong(id: id, title: title, artist: artist)
        case .episode(let id, let title, let streamURL):
            guard let url = URL(string: streamURL) else { return }
            let episode = RSSEpisode(
                id: id,
                title: title,
                summary: "",
                published: nil,
                duration: nil,
                audioURL: url
            )
            await playEpisode(episode, show: alarm.label, artwork: nil, resume: 0, localURL: localEpisodeURL)
        }
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        switch source {
        case .music:
            ApplicationMusicPlayer.shared.pause()
            stopMusicPoll()
        case .episode:
            player.pause()
        case .idle:
            break
        }
        isPlaying = false
        publishNowPlaying()
    }

    func resume() {
        switch source {
        case .music:
            Task { try? await ApplicationMusicPlayer.shared.play() }
            isPlaying = true
            startMusicPoll()
        case .episode:
            player.play()
            player.rate = rate
            isPlaying = true
        case .idle:
            break
        }
        publishNowPlaying()
    }

    func seek(to seconds: TimeInterval) {
        let target = PlaybackSkip.seek(current: 0, duration: duration > 0 ? duration : nil, delta: seconds)
        switch source {
        case .music:
            ApplicationMusicPlayer.shared.playbackTime = target
            currentTime = target
        case .episode:
            let time = CMTime(seconds: target, preferredTimescale: 600)
            player.seek(to: time)
            currentTime = target
        case .idle:
            break
        }
        publishNowPlaying()
    }

    func skip(by delta: TimeInterval) {
        let target = PlaybackSkip.seek(
            current: currentTime,
            duration: duration > 0 ? duration : nil,
            delta: delta
        )
        seek(to: target)
    }

    func setRate(_ newRate: Float) {
        rate = PlaybackRate.clamped(newRate)
        if isPlaying, case .episode = source {
            player.rate = rate
        }
        publishNowPlaying()
    }

    func startSleep(minutes: Int) {
        guard minutes > 0 else { return }
        sleep = SleepFade(startedAt: Date(), duration: TimeInterval(minutes * 60))
        armSleep()
    }

    func startSleepUntilEnd() {
        let remain = max(0, duration - currentTime)
        guard remain > 1 else { return }
        sleep = SleepFade(startedAt: Date(), duration: remain)
        armSleep()
    }

    func cancelSleep() {
        sleepTask?.cancel()
        sleep = nil
        sleepRemaining = nil
        if case .episode = source {
            player.volume = 1
        }
    }

    private func armSleep() {
        sleepTask?.cancel()
        sleepTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let sleep else { return }
                let now = Date()
                if case .episode = source {
                    player.volume = Float(sleep.volume(at: now))
                }
                sleepRemaining = sleep.remaining(at: now)
                if sleep.isFinished(at: now) {
                    pause()
                    self.sleep = nil
                    sleepRemaining = nil
                    if case .episode = source {
                        player.volume = 1
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func remember(_ songs: [Song]) -> [SongSnapshot] {
        songs.map { song in
            self.songs[song.id.rawValue] = song
            return SongSnapshot(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                artwork: song.artwork?.url(width: 400, height: 400),
                duration: song.duration ?? 0
            )
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func pauseEpisode() {
        player.pause()
    }

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.4, preferredTimescale: 600)
        timeToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard case .episode(let id, _, _, _) = self.source else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                let itemDuration = self.player.currentItem?.duration.seconds ?? 0
                if itemDuration.isFinite && itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.isPlaying = self.player.rate > 0.05
                self.progressHandler?(id, self.currentTime, self.duration)
                self.publishNowPlaying()
            }
        }
    }

    private func installEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .episode(let id, _, _, _) = self.source else { return }
                self.isPlaying = false
                self.progressHandler?(id, self.duration, self.duration)
                self.publishNowPlaying()
            }
        }
    }

    private func startMusicPoll() {
        musicPoll?.cancel()
        musicPoll = Task { @MainActor in
            while !Task.isCancelled {
                let musicPlayer = ApplicationMusicPlayer.shared
                currentTime = musicPlayer.playbackTime
                isPlaying = musicPlayer.state.playbackStatus == .playing
                publishNowPlaying()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func stopMusicPoll() {
        musicPoll?.cancel()
        musicPoll = nil
    }

    private func installRemoteCommands() {
        guard !remoteInstalled else { return }
        remoteInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipBackwardCommand.preferredIntervals = [15]

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 30) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -15) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func publishNowPlaying() {
        guard source != .idle else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rateOrOne) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rateOrOne),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        guard let artworkURL else { return }
        let title = title
        let artist = subtitle
        Task { @MainActor in
            guard self.artworkURL == artworkURL, let (data, _) = try? await URLSession.shared.data(from: artworkURL),
                  let image = UIImage(data: data) else { return }
            var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
            updated[MPMediaItemPropertyTitle] = title
            updated[MPMediaItemPropertyArtist] = artist
            updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
    }

    private var rateOrOne: Float {
        if case .music = source { return 1 }
        return rate
    }
}
