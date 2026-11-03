import XCTest
@testable import IpduoClockCore

final class FoldLayoutTests: XCTestCase {
    func testNoDivisionUsesTheFullContainer() {
        let frame = FoldLayout.contentFrame(containerWidth: 400, containerHeight: 800, division: nil)
        XCTAssertEqual(frame, LayoutRect(x: 0, y: 0, width: 400, height: 800))
    }

    func testVerticalFoldKeepsContentOnTheLeadingSideWhenThePanesMatch() {
        let division = LayoutRect(x: 190, y: 0, width: 20, height: 800)
        let frame = FoldLayout.contentFrame(containerWidth: 400, containerHeight: 800, division: division)
        XCTAssertEqual(frame, LayoutRect(x: 0, y: 0, width: 190, height: 800))
        XCTAssertFalse(frame.intersects(division))
    }

    func testVerticalFoldPrefersTheLargerPane() {
        let division = LayoutRect(x: 100, y: 0, width: 20, height: 500)
        let frame = FoldLayout.contentFrame(containerWidth: 400, containerHeight: 500, division: division)
        XCTAssertEqual(frame.minX, 120, accuracy: 0.001)
        XCTAssertEqual(frame.width, 280, accuracy: 0.001)
        XCTAssertFalse(frame.intersects(division))
    }

    func testHorizontalFoldKeepsContentAboveTheHingeWhenThePanesMatch() {
        let division = LayoutRect(x: 0, y: 240, width: 600, height: 20)
        let frame = FoldLayout.contentFrame(containerWidth: 600, containerHeight: 500, division: division)
        XCTAssertEqual(frame, LayoutRect(x: 0, y: 0, width: 600, height: 240))
        XCTAssertFalse(frame.intersects(division))
    }

    func testOcclusionAtTheTopPushesContentDown() {
        let camera = LayoutRect(x: 300, y: 0, width: 100, height: 40)
        let frame = FoldLayout.contentFrame(
            containerWidth: 400,
            containerHeight: 800,
            division: nil,
            occlusions: [camera]
        )
        XCTAssertGreaterThanOrEqual(frame.minY, 40)
        XCTAssertFalse(frame.intersects(camera))
    }

    func testEvenColumns() {
        XCTAssertEqual(FoldLayout.evenColumnCount(containerWidth: 300, minimumColumnWidth: 160), 1)
        XCTAssertEqual(FoldLayout.evenColumnCount(containerWidth: 400, minimumColumnWidth: 160), 2)
        XCTAssertEqual(FoldLayout.evenColumnCount(containerWidth: 700, minimumColumnWidth: 160), 4)
        XCTAssertEqual(FoldLayout.evenColumnCount(containerWidth: 500, minimumColumnWidth: 160), 2)
        let verticalFold = LayoutRect(x: 200, y: 0, width: 16, height: 400)
        XCTAssertEqual(
            FoldLayout.evenColumnCount(containerWidth: 500, minimumColumnWidth: 160, division: verticalFold),
            2
        )
        let horizontalFold = LayoutRect(x: 0, y: 200, width: 400, height: 16)
        XCTAssertEqual(
            FoldLayout.evenColumnCount(containerWidth: 700, minimumColumnWidth: 160, division: horizontalFold),
            4
        )
    }
}
