import XCTest

@testable import LivelineKit

final class HitTestTests: XCTestCase {
    let times = [0.0, 1, 2, 3, 4, 5]

    func testExactMatch() {
        XCTAssertEqual(HitTest.nearest(times: times, x: 3), 3)
    }

    func testNearestRoundsToCloser() {
        XCTAssertEqual(HitTest.nearest(times: times, x: 2.4), 2)
        XCTAssertEqual(HitTest.nearest(times: times, x: 2.6), 3)
    }

    func testTieResolvesToEarlier() {
        XCTAssertEqual(HitTest.nearest(times: times, x: 2.5), 2)
    }

    func testBelowRangeClampsToFirst() {
        XCTAssertEqual(HitTest.nearest(times: times, x: -10), 0)
    }

    func testAboveRangeClampsToLast() {
        XCTAssertEqual(HitTest.nearest(times: times, x: 99), 5)
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(HitTest.nearest(times: [], x: 1))
    }

    func testUnevenSpacing() {
        let uneven = [0.0, 10, 12, 100]
        XCTAssertEqual(HitTest.nearest(times: uneven, x: 11.4), 2)
        XCTAssertEqual(HitTest.nearest(times: uneven, x: 6), 1)
    }
}
