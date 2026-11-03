import IpduoClockCore
import SwiftUI
import UIKit

/// Launch-argument tour used by the UI test on GitHub Actions.
/// `-ipduo-screen <name>` seeds a deterministic state and skips permission prompts.
enum ScreenshotSession {
    static let podcastQuery = "radiolab"

    static var screen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ipduo-screen"), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        return value.hasPrefix("-") ? nil : value
    }

    static var isActive: Bool { screen != nil }

    static var wantsLandscape: Bool {
        guard let screen else { return false }
        return screen == "standby" || screen.hasPrefix("regular-")
    }

    static func face(for screen: String) -> ClockFaceID {
        switch screen {
        case "clock-digital": return .digital
        case "clock-flip": return .flip
        case "clock-ambient": return .ambient
        default: return .analog
        }
    }

    static func tab(for screen: String) -> AppTab {
        switch screen {
        case "world", "regular-world": return .world
        case "alarms", "add-alarm", "regular-alarms": return .alarms
        case "timer", "stopwatch", "regular-timers": return .timers
        case "listen-music", "listen-podcasts": return .listen
        default: return .clock
        }
    }
}

@MainActor
enum OrientationLock {
    static func apply(landscape: Bool) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscape : .portrait
        AppDelegate.orientationMask = mask
        let orientation: UIInterfaceOrientationMask = landscape ? .landscapeLeft : .portrait
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { _ in }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

struct ScreenshotMarker: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if model.screenshotScreen != nil {
                Text(model.screenshotReady ? "screenshot-ready" : "screenshot-pending")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.02))
                    .frame(width: 24, height: 16, alignment: .leading)
                    .accessibilityIdentifier(model.screenshotReady ? "screenshot-ready" : "screenshot-pending")
                    .accessibilityLabel(model.screenshotReady ? "screenshot-ready" : "screenshot-pending")
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func screenshotMarker() -> some View {
        modifier(ScreenshotMarker())
    }
}

@MainActor
enum ScreenshotDirector {
    static func prepare(model: AppModel, playback: PlaybackCenter, podcasts: PodcastClient) async {
        guard let screen = model.screenshotScreen else { return }
        let landscape = ScreenshotSession.wantsLandscape
        OrientationLock.apply(landscape: landscape)
        try? await Task.sleep(nanoseconds: 350_000_000)
        OrientationLock.apply(landscape: landscape)
        // Page-style TabView sometimes ignores the selection it was created with.
        let face = model.face
        model.face = face == .analog ? .digital : .analog
        model.face = face

        switch screen {
        case "listen-podcasts":
            _ = await search(podcasts, model: model, preferred: ScreenshotSession.podcastQuery)
            resignKeyboard()
        case "mini-player", "now-playing":
            let playing = await playFirstEpisode(model: model, playback: playback, podcasts: podcasts)
            if screen == "mini-player" {
                model.tab = .clock
                model.face = .analog
                model.nowPlayingPresented = false
            } else if playing {
                model.nowPlayingPresented = true
            }
        default:
            break
        }

        let settle: UInt64 = landscape ? 900_000_000 : 450_000_000
        try? await Task.sleep(nanoseconds: settle)
        model.screenshotReady = true
    }

    private static func search(_ podcasts: PodcastClient, model: AppModel, preferred: String) async -> Bool {
        let terms = [preferred, "npr", "news"]
        for term in terms {
            model.screenshotSearchTerm = term
            for _ in 0..<3 {
                await podcasts.search(term)
                if !podcasts.results.isEmpty { return true }
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
        }
        return false
    }

    private static func playFirstEpisode(
        model: AppModel,
        playback: PlaybackCenter,
        podcasts: PodcastClient
    ) async -> Bool {
        let terms = [ScreenshotSession.podcastQuery, "npr", "news"]
        for term in terms {
            for _ in 0..<2 {
                await podcasts.search(term)
                if podcasts.results.isEmpty {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    continue
                }
                for show in podcasts.results.prefix(3) {
                    guard show.feed != nil else { continue }
                    model.subscribe(show)
                    guard let subscription = model.subscriptions.first(where: { $0.id == show.collectionId }) else { continue }
                    await podcasts.load(subscription, model: model)
                    let episodes = podcasts.episodes[show.collectionId] ?? []
                    guard let episode = episodes.first(where: { $0.audioURL.scheme == "https" || $0.audioURL.scheme == "http" }) else { continue }
                    await playback.playEpisode(
                        episode,
                        show: show.collectionName,
                        artwork: show.artworkURL,
                        resume: 0,
                        localURL: nil
                    )
                    if playback.source != .idle { return true }
                }
            }
        }
        return false
    }

    private static func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
