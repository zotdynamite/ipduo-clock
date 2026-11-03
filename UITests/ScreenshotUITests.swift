import UIKit
import XCTest

final class ScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 1800
    }

    func testScreenshots() throws {
        let directory = screenshotDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let portrait = [
            "clock-analog",
            "clock-digital",
            "clock-flip",
            "clock-ambient",
            "world",
            "alarms",
            "add-alarm",
            "timer",
            "stopwatch",
            "listen-music",
            "listen-podcasts",
            "mini-player",
            "now-playing",
            "settings"
        ]
        for name in portrait {
            try capture(name, landscape: false, directory: directory)
        }
        try capture("standby", landscape: true, directory: directory)
        try capture("regular-clock", landscape: true, directory: directory)
        try capture("regular-world", landscape: true, directory: directory)
        try capture("regular-alarms", landscape: true, directory: directory)
        try capture("regular-timers", landscape: true, directory: directory)
    }

    private func capture(_ name: String, landscape: Bool, directory: URL) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ipduo-screen", name,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        let orientation: UIDeviceOrientation = landscape ? .landscapeLeft : .portrait
        XCUIDevice.shared.orientation = orientation
        app.launch()
        XCUIDevice.shared.orientation = orientation

        let readyTimeout: TimeInterval = (name == "listen-podcasts" || name == "mini-player" || name == "now-playing") ? 90 : 25
        let ready = app.descendants(matching: .any)["screenshot-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: readyTimeout), "Timed out waiting for \(name)")
        waitForOrientation(landscape: landscape, app: app)
        RunLoop.current.run(until: Date().addingTimeInterval(landscape ? 1.0 : 0.6))

        assertContent(name, app: app)

        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = fileName(for: name)
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = directory.appendingPathComponent(fileName(for: name) + ".png")
        try shot.pngRepresentation.write(to: url, options: .atomic)
        app.terminate()
    }

    private func assertContent(_ name: String, app: XCUIApplication) {
        switch name {
        case "clock-analog":
            XCTAssertTrue(app.descendants(matching: .any)["face-analog"].waitForExistence(timeout: 5))
        case "clock-digital":
            XCTAssertTrue(app.descendants(matching: .any)["face-digital"].waitForExistence(timeout: 5))
        case "clock-flip":
            XCTAssertTrue(app.descendants(matching: .any)["face-flip"].waitForExistence(timeout: 5))
        case "clock-ambient":
            XCTAssertTrue(app.descendants(matching: .any)["face-ambient"].waitForExistence(timeout: 5))
        case "world":
            XCTAssertTrue(app.staticTexts["Tokyo"].waitForExistence(timeout: 5))
        case "alarms":
            XCTAssertTrue(app.staticTexts["Wake"].waitForExistence(timeout: 5))
        case "add-alarm":
            XCTAssertTrue(app.buttons["Save Alarm"].waitForExistence(timeout: 5))
        case "timer":
            XCTAssertTrue(app.buttons["5m"].waitForExistence(timeout: 5))
        case "stopwatch":
            XCTAssertTrue(app.staticTexts["Lap 1"].waitForExistence(timeout: 5))
        case "listen-music":
            XCTAssertTrue(app.staticTexts["Apple Music"].waitForExistence(timeout: 5))
        case "listen-podcasts":
            XCTAssertTrue(app.buttons["Subscribe"].waitForExistence(timeout: 8), "Expected live iTunes podcast results")
        case "mini-player":
            XCTAssertTrue(app.buttons["Pause"].exists || app.buttons["Play"].waitForExistence(timeout: 5))
        case "now-playing":
            XCTAssertTrue(app.navigationBars["Now Playing"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Nothing playing"].exists)
        case "settings":
            XCTAssertTrue(app.staticTexts["24-hour clock"].waitForExistence(timeout: 5))
        case "standby":
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        case "regular-clock":
            XCTAssertTrue(app.staticTexts["World Clock"].waitForExistence(timeout: 5), "Expected the regular-width side column")
        case "regular-world":
            XCTAssertTrue(app.staticTexts["Sunrise"].waitForExistence(timeout: 5))
        case "regular-alarms":
            XCTAssertTrue(app.buttons["Edit Alarm"].waitForExistence(timeout: 5))
        case "regular-timers":
            XCTAssertTrue(app.buttons["5m"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Lap"].exists)
        default:
            break
        }
    }

    private func waitForOrientation(landscape: Bool, app: XCUIApplication) {
        let start = Date()
        while Date().timeIntervalSince(start) < 8 {
            let frame = app.frame
            if frame.width > 1, frame.height > 1 {
                if landscape, frame.width > frame.height { return }
                if !landscape, frame.height >= frame.width { return }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("Orientation did not settle for landscape=\(landscape). frame=\(app.frame)")
    }

    private func fileName(for screen: String) -> String {
        switch screen {
        case "clock-analog": return "01-clock-analog-iphone"
        case "clock-digital": return "02-clock-digital-iphone"
        case "clock-flip": return "03-clock-flip-iphone"
        case "clock-ambient": return "04-clock-ambient-iphone"
        case "world": return "05-world-iphone"
        case "alarms": return "06-alarms-iphone"
        case "add-alarm": return "07-add-alarm-iphone"
        case "timer": return "08-timer-iphone"
        case "stopwatch": return "09-stopwatch-iphone"
        case "listen-music": return "10-listen-music-unauthorized-iphone"
        case "listen-podcasts": return "11-listen-podcasts-iphone"
        case "mini-player": return "12-mini-player-iphone"
        case "now-playing": return "13-now-playing-iphone"
        case "standby": return "14-standby-landscape-iphone"
        case "settings": return "15-settings-iphone"
        case "regular-clock": return "16-regular-clock-landscape"
        case "regular-world": return "17-regular-world-landscape"
        case "regular-alarms": return "18-regular-alarms-landscape"
        case "regular-timers": return "19-regular-timers-landscape"
        default: return screen
        }
    }

    private func screenshotDirectory() -> URL {
        if let raw = ProcessInfo.processInfo.environment["IPDUO_SCREENSHOT_DIR"], !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return URL(fileURLWithPath: "/tmp/ipduo-screenshots", isDirectory: true)
    }
}
