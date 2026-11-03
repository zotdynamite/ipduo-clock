import Foundation
import IpduoClockCore
import SwiftUI

@MainActor
final class PodcastClient: ObservableObject {
    @Published var results: [PodcastDirectoryEntry] = []
    @Published var episodes: [Int: [RSSEpisode]] = [:]
    @Published var loading = false
    @Published var message: String?

    func search(_ term: String) async {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        guard let url = PodcastDirectory.searchURL(term: trimmed) else { return }
        loading = true
        defer { loading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            results = try PodcastDirectory.decode(data).results
            message = results.isEmpty ? "No shows found." : nil
        } catch {
            message = error.localizedDescription
        }
    }

    func load(_ subscription: PodcastSubscription, model: AppModel) async {
        loading = true
        defer { loading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: subscription.feedURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard let feed = RSSParser.parse(data) else {
                throw URLError(.cannotParseResponse)
            }
            episodes[subscription.id] = feed.episodes
            if let index = model.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                model.subscriptions[index].cachedEpisodes = feed.episodes.prefix(40).map {
                    CachedEpisode(id: $0.id, title: $0.title, streamURL: $0.audioURL.absoluteString)
                }
                model.touch()
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func download(_ episode: RSSEpisode, model: AppModel) async {
        if model.localFile(for: episode.id) != nil { return }
        do {
            let (temporary, response) = try await URLSession.shared.download(from: episode.audioURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let ext = episode.audioURL.pathExtension.isEmpty ? "mp3" : episode.audioURL.pathExtension
            let filename = "\(stableName(episode.id)).\(ext)"
            let destination = AppModel.downloadsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
            model.setDownload(episodeID: episode.id, filename: filename)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func removeDownload(_ episodeID: String, model: AppModel) {
        model.setDownload(episodeID: episodeID, filename: nil)
    }

    private func stableName(_ id: String) -> String {
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
