import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct RSSEpisode: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var published: Date?
    public var duration: TimeInterval?
    public var audioURL: URL

    public init(
        id: String,
        title: String,
        summary: String,
        published: Date?,
        duration: TimeInterval?,
        audioURL: URL
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.published = published
        self.duration = duration
        self.audioURL = audioURL
    }
}

public struct RSSFeed: Equatable {
    public var title: String
    public var author: String
    public var episodes: [RSSEpisode]

    public init(title: String, author: String, episodes: [RSSEpisode]) {
        self.title = title
        self.author = author
        self.episodes = episodes
    }
}

public enum DurationParser {
    public static func parse(_ raw: String) -> TimeInterval? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let pieces = text.split(separator: ":").map(String.init)
        let numbers = pieces.compactMap(Double.init)
        guard numbers.count == pieces.count, !numbers.isEmpty else { return nil }
        switch numbers.count {
        case 1:
            return numbers[0]
        case 2:
            return numbers[0] * 60 + numbers[1]
        case 3:
            return numbers[0] * 3600 + numbers[1] * 60 + numbers[2]
        default:
            return nil
        }
    }
}

public enum HTMLText {
    public static func plain(_ raw: String) -> String {
        var text = raw
        let entities = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " ")
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum RSSParser {
    public static func parse(_ data: Data) -> RSSFeed? {
        guard !data.isEmpty else { return nil }
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            if delegate.sawChannel { return delegate.makeFeed() }
            return nil
        }
        guard delegate.sawChannel else { return nil }
        return delegate.makeFeed()
    }

    public static func parse(_ xml: String) -> RSSFeed? {
        parse(Data(xml.utf8))
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    private(set) var sawChannel = false
    private var channelTitle = ""
    private var channelAuthor = ""
    private var episodes: [RSSEpisode] = []

    private var stack: [String] = []
    private var text = ""
    private var inItem = false
    private var itemTitle = ""
    private var itemSummary = ""
    private var itemGUID = ""
    private var itemDate = ""
    private var itemDuration = ""
    private var itemURL: URL?

    func makeFeed() -> RSSFeed {
        RSSFeed(title: channelTitle, author: channelAuthor, episodes: episodes)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(qName ?? elementName)
        stack.append(name)
        text = ""
        if name == "channel" { sawChannel = true }
        if name == "item" {
            inItem = true
            itemTitle = ""
            itemSummary = ""
            itemGUID = ""
            itemDate = ""
            itemDuration = ""
            itemURL = nil
        }
        if name == "enclosure", inItem, let raw = attributeDict["url"], let url = URL(string: raw) {
            itemURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            text += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(qName ?? elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch name {
            case "title": itemTitle = HTMLText.plain(value)
            case "guid": itemGUID = value
            case "pubdate", "published", "date": itemDate = value
            case "duration": itemDuration = value
            case "summary", "description", "subtitle":
                if itemSummary.isEmpty { itemSummary = HTMLText.plain(value) }
            case "item":
                if let url = itemURL {
                    let id = itemGUID.isEmpty ? url.absoluteString : itemGUID
                    episodes.append(RSSEpisode(
                        id: id,
                        title: itemTitle.isEmpty ? "Episode" : itemTitle,
                        summary: itemSummary,
                        published: RFC822.parse(itemDate),
                        duration: DurationParser.parse(itemDuration),
                        audioURL: url
                    ))
                }
                inItem = false
            default:
                break
            }
        } else if stack.contains("channel") {
            switch name {
            case "title":
                if channelTitle.isEmpty { channelTitle = HTMLText.plain(value) }
            case "author":
                if channelAuthor.isEmpty { channelAuthor = HTMLText.plain(value) }
            default:
                break
            }
        }
        if stack.last == name { stack.removeLast() }
        text = ""
    }

    private func localName(_ raw: String) -> String {
        raw.split(separator: ":").last.map(String.init)?.lowercased() ?? raw.lowercased()
    }
}

enum RFC822 {
    static func parse(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
