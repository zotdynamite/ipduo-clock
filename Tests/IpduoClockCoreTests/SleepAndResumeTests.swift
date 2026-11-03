import XCTest
@testable import IpduoClockCore

final class SleepAndResumeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testSleepTimerHoldsThenFadesThenFinishes() {
        let fade = SleepFade(startedAt: start, duration: 60, fadeDuration: 15)
        XCTAssertEqual(fade.volume(at: start), 1)
        if case .holding(_, let remaining) = fade.phase(at: start.addingTimeInterval(44)) {
            XCTAssertEqual(remaining, 16, accuracy: 0.001)
        } else {
            XCTFail("Expected the timer to still be holding at 44 seconds")
        }

        let mid = fade.phase(at: start.addingTimeInterval(52.5))
        guard case .fading(let volume, let remaining) = mid else {
            return XCTFail("Expected a fade, got \(mid)")
        }
        XCTAssertEqual(remaining, 7.5, accuracy: 0.001)
        XCTAssertEqual(volume, 0.5, accuracy: 0.001)

        XCTAssertTrue(fade.isFinished(at: start.addingTimeInterval(60)))
        XCTAssertEqual(fade.volume(at: start.addingTimeInterval(60)), 0)
        XCTAssertTrue(fade.isFinished(at: start.addingTimeInterval(90)))
        XCTAssertEqual(fade.remaining(at: start.addingTimeInterval(90)), 0)
    }

    func testSleepTimerWithoutAFadeStopsCleanly() {
        let fade = SleepFade(startedAt: start, duration: 30, fadeDuration: 0)
        XCTAssertEqual(fade.volume(at: start.addingTimeInterval(29)), 1)
        XCTAssertTrue(fade.isFinished(at: start.addingTimeInterval(30)))
    }

    func testFadeCannotBeLongerThanTheTimer() {
        let fade = SleepFade(startedAt: start, duration: 10, fadeDuration: 40)
        let phase = fade.phase(at: start.addingTimeInterval(5))
        guard case .fading(let volume, _) = phase else {
            return XCTFail("A fade longer than the timer should fade the whole way")
        }
        XCTAssertEqual(volume, 0.5, accuracy: 0.001)
    }

    func testResumeIgnoresTheOpeningSecondsAndClearsAFinishedEpisode() {
        var book = ResumeBook()
        book.record(id: "a", seconds: 1, duration: 100)
        XCTAssertEqual(book.position(for: "a"), 0)

        book.record(id: "a", seconds: 40, duration: 100)
        XCTAssertEqual(book.position(for: "a"), 40)
        XCTAssertEqual(book.fraction(id: "a", duration: 100) ?? -1, 0.4, accuracy: 0.001)

        book.record(id: "a", seconds: 99, duration: 100)
        XCTAssertEqual(book.position(for: "a"), 0)
        XCTAssertNil(book.fraction(id: "a", duration: 100))
    }

    func testResumeWithoutAKnownDurationStillRemembersThePlayhead() {
        var book = ResumeBook()
        book.record(id: "live", seconds: 12, duration: nil)
        XCTAssertEqual(book.position(for: "live"), 12)
        XCTAssertNil(book.fraction(id: "live", duration: nil))
    }

    func testSkipClampsToTheEpisode() {
        XCTAssertEqual(PlaybackSkip.seek(current: 50, duration: 100, delta: 30), 80)
        XCTAssertEqual(PlaybackSkip.seek(current: 90, duration: 100, delta: 30), 100)
        XCTAssertEqual(PlaybackSkip.seek(current: 10, duration: 100, delta: -15), 0)
        XCTAssertEqual(PlaybackSkip.seek(current: 40, duration: 100, delta: -15), 25)
        XCTAssertEqual(PlaybackSkip.seek(current: 5, duration: nil, delta: 30), 35)
        XCTAssertEqual(PlaybackSkip.seek(current: 4, duration: nil, delta: -30), 0)
    }

    func testPlaybackRatesStayInRange() {
        XCTAssertEqual(PlaybackRate.clamped(3), 2)
        XCTAssertEqual(PlaybackRate.clamped(0.1), 0.5)
        XCTAssertEqual(PlaybackRate.clamped(1.25), 1.25)
        XCTAssertEqual(PlaybackRate.presets, [0.75, 1, 1.25, 1.5, 1.75, 2])
        XCTAssertEqual(PlaybackRate.label(1), "1×")
        XCTAssertEqual(PlaybackRate.label(1.5), "1.5×")
    }
}
