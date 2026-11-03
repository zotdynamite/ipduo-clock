import XCTest
@testable import IpduoClockCore

final class StopwatchCountdownTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testStopwatchRunPauseLapAndReset() {
        var watch = StopwatchState()
        XCTAssertEqual(watch.elapsed(at: start), 0)
        watch.start(at: start)
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(10)), 10, accuracy: 0.001)
        watch.lap(at: start.addingTimeInterval(10))
        watch.lap(at: start.addingTimeInterval(25))
        XCTAssertEqual(watch.laps.map(\.index), [2, 1])
        XCTAssertEqual(watch.laps.map(\.split), [15, 10])
        XCTAssertEqual(watch.laps.map(\.total), [25, 10])

        watch.pause(at: start.addingTimeInterval(30))
        XCTAssertFalse(watch.isRunning)
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(100)), 30, accuracy: 0.001)

        watch.start(at: start.addingTimeInterval(100))
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(110)), 40, accuracy: 0.001)
        watch.reset()
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(200)), 0)
        XCTAssertTrue(watch.laps.isEmpty)
    }

    func testStartingTwiceDoesNotResetTheClock() {
        var watch = StopwatchState()
        watch.start(at: start)
        watch.start(at: start.addingTimeInterval(5))
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(5)), 5, accuracy: 0.001)
    }

    func testElapsedFormat() {
        XCTAssertEqual(ElapsedFormat.string(from: 65), "01:05.00")
        XCTAssertEqual(ElapsedFormat.string(from: 65.5), "01:05.50")
        XCTAssertEqual(ElapsedFormat.string(from: 3661), "1:01:01.00")
    }

    func testCountdownProgressPauseAndFinish() {
        var timer = CountdownState(duration: 60)
        XCTAssertEqual(timer.progress(at: start), 0)
        timer.start(at: start)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(15)), 45, accuracy: 0.001)
        XCTAssertEqual(timer.progress(at: start.addingTimeInterval(15)), 0.25, accuracy: 0.001)
        XCTAssertFalse(timer.isFinished(at: start.addingTimeInterval(15)))

        timer.pause(at: start.addingTimeInterval(15))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(100)), 45, accuracy: 0.001)

        timer.start(at: start.addingTimeInterval(100))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(110)), 35, accuracy: 0.001)
        XCTAssertTrue(timer.isFinished(at: start.addingTimeInterval(145)))
        XCTAssertEqual(timer.progress(at: start.addingTimeInterval(145)), 1, accuracy: 0.001)
        XCTAssertEqual(CountdownFormat.clock(3599), "59:59")
        XCTAssertEqual(CountdownFormat.clock(3600), "1:00:00")
    }

    func testChangingDurationWhilePausedResetsTheRemainingTime() {
        var timer = CountdownState(duration: 30)
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(10))
        timer.setDuration(90)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(50)), 90, accuracy: 0.001)
        timer.reset()
        XCTAssertEqual(timer.remaining(at: start), 90, accuracy: 0.001)
    }

    func testZeroDurationIsAlreadyComplete() {
        let timer = CountdownState(duration: 0)
        XCTAssertEqual(timer.progress(at: start), 1)
        XCTAssertFalse(timer.isFinished(at: start))
    }
}
