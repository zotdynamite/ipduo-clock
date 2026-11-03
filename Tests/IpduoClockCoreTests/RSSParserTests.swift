import XCTest
@testable import IpduoClockCore

final class RSSParserTests: XCTestCase {
    private let feedXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
      <channel>
        <title>Night Desk</title>
        <itunes:author>Ipduo Radio</itunes:author>
        <item>
          <title><![CDATA[Dawn Chorus]]></title>
          <guid>ep-1</guid>
          <pubDate>Mon, 02 Nov 2026 07:00:00 GMT</pubDate>
          <itunes:duration>01:02:03</itunes:duration>
          <enclosure url="https://example.com/dawn.mp3" type="audio/mpeg" length="1000"/>
          <description>Birds at &amp; before sunrise. &lt;em&gt;Quiet.&lt;/em&gt;</description>
        </item>
        <item>
          <title>City Lights</title>
          <guid>ep-2</guid>
          <itunes:duration>125</itunes:duration>
          <enclosure url="https://example.com/city.mp3" type="audio/mpeg"/>
          <itunes:summary><![CDATA[<p>Neon and rain.</p>]]></itunes:summary>
        </item>
        <item>
          <title>No Audio</title>
          <guid>ep-skip</guid>
          <description>A trailer without a file.</description>
        </item>
        <item>
          <title></title>
          <itunes:duration>62:03</itunes:duration>
          <enclosure url="https://example.com/fallback.mp3" type="audio/mpeg"/>
        </item>
      </channel>
    </rss>
    """

    func testParsesChannelEpisodesDurationsAndSkipsItemsWithoutAudio() {
        let feed = RSSParser.parse(feedXML)
        XCTAssertEqual(feed?.title, "Night Desk")
        XCTAssertEqual(feed?.author, "Ipduo Radio")
        XCTAssertEqual(feed?.episodes.map(\.id), ["ep-1", "ep-2", "https://example.com/fallback.mp3"])

        let dawn = feed?.episodes[0]
        XCTAssertEqual(dawn?.title, "Dawn Chorus")
        XCTAssertEqual(dawn?.summary, "Birds at & before sunrise. Quiet.")
        XCTAssertEqual(dawn?.duration, 3723)
        XCTAssertEqual(dawn?.audioURL.absoluteString, "https://example.com/dawn.mp3")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = utc.dateComponents([.year, .month, .day, .hour], from: dawn!.published!)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 2)
        XCTAssertEqual(parts.hour, 7)

        XCTAssertEqual(feed?.episodes[1].duration, 125)
        XCTAssertEqual(feed?.episodes[1].summary, "Neon and rain.")
        XCTAssertEqual(feed?.episodes[2].title, "Episode")
        XCTAssertEqual(feed?.episodes[2].duration, 62 * 60 + 3)
    }

    func testDurationFormatsAndEmptyInput() {
        XCTAssertEqual(DurationParser.parse("01:02:03"), 3723)
        XCTAssertEqual(DurationParser.parse("1:02"), 62)
        XCTAssertEqual(DurationParser.parse("90"), 90)
        XCTAssertNil(DurationParser.parse("soon"))
        XCTAssertNil(DurationParser.parse(""))
        XCTAssertNil(RSSParser.parse(""))
        XCTAssertNil(RSSParser.parse("<not-a-feed></not-a-feed>"))
    }

    func testDirectoryJSONAndSearchURL() {
        let json = """
        {
          "resultCount": 1,
          "results": [
            {
              "collectionId": 42,
              "collectionName": "Night Desk",
              "artistName": "Ipduo Radio",
              "feedUrl": "https://example.com/feed.xml",
              "artworkUrl600": "https://example.com/art.jpg"
            }
          ]
        }
        """.data(using: .utf8)!
        let page = try! PodcastDirectory.decode(json)
        XCTAssertEqual(page.results.count, 1)
        XCTAssertEqual(page.results[0].id, 42)
        XCTAssertEqual(page.results[0].feed?.absoluteString, "https://example.com/feed.xml")
        XCTAssertEqual(page.results[0].artworkURL?.absoluteString, "https://example.com/art.jpg")

        let url = PodcastDirectory.searchURL(term: "Dawn Chorus", limit: 10)!
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertTrue(url.query?.contains("media=podcast") == true)
        XCTAssertTrue(url.query?.contains("entity=podcast") == true)
        XCTAssertTrue(url.absoluteString.contains("Dawn%20Chorus") || url.absoluteString.contains("Dawn+Chorus"))
        let lookup = PodcastDirectory.lookupURL(collectionID: 42)!
        XCTAssertTrue(lookup.absoluteString.contains("id=42"))
    }
}
