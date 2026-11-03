import Foundation

public struct PodcastDirectoryEntry: Codable, Equatable, Identifiable {
    public var collectionId: Int
    public var collectionName: String
    public var artistName: String
    public var feedUrl: String?
    public var artworkUrl600: String?
    public var artworkUrl100: String?

    public var id: Int { collectionId }

    public init(
        collectionId: Int,
        collectionName: String,
        artistName: String,
        feedUrl: String? = nil,
        artworkUrl600: String? = nil,
        artworkUrl100: String? = nil
    ) {
        self.collectionId = collectionId
        self.collectionName = collectionName
        self.artistName = artistName
        self.feedUrl = feedUrl
        self.artworkUrl600 = artworkUrl600
        self.artworkUrl100 = artworkUrl100
    }

    public var artworkURL: URL? {
        if let artworkUrl600, let url = URL(string: artworkUrl600) { return url }
        if let artworkUrl100, let url = URL(string: artworkUrl100) { return url }
        return nil
    }

    public var feed: URL? {
        feedUrl.flatMap(URL.init(string:))
    }
}

public struct PodcastDirectoryPage: Codable, Equatable {
    public var resultCount: Int?
    public var results: [PodcastDirectoryEntry]

    public init(resultCount: Int? = nil, results: [PodcastDirectoryEntry]) {
        self.resultCount = resultCount
        self.results = results
    }
}

public enum PodcastDirectory {
    public static func searchURL(term: String, limit: Int = 25) -> URL? {
        url(path: "https://itunes.apple.com/search", items: [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 50))))
        ])
    }

    public static func lookupURL(collectionID: Int) -> URL? {
        url(path: "https://itunes.apple.com/lookup", items: [
            URLQueryItem(name: "id", value: String(collectionID)),
            URLQueryItem(name: "entity", value: "podcast")
        ])
    }

    public static func decode(_ data: Data) throws -> PodcastDirectoryPage {
        let decoder = JSONDecoder()
        return try decoder.decode(PodcastDirectoryPage.self, from: data)
    }

    private static func url(path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: path)
        components?.queryItems = items
        return components?.url
    }
}
