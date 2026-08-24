import XCTest

@testable import LivelineKit

final class InterpolateTests: XCTestCase {
    let points = [
        LivelinePoint(time: 0, value: 0),
        LivelinePoint(time: 10, value: 100),
        LivelinePoint(time: 20, value: 50),
    ]

    func testInterpolatesMidSegment() {
        XCTAssertEqual(Interpolate.atTime(points, time: 5) ?? .nan, 50, accuracy: 1e-9)
        XCTAssertEqual(Interpolate.atTime(points, time: 15) ?? .nan, 75, accuracy: 1e-9)
    }

    func testClampsBelowAndAbove() {
        XCTAssertEqual(Interpolate.atTime(points, time: -5), 0)
        XCTAssertEqual(Interpolate.atTime(points, time: 100), 50)
    }

    func testExactVertices() {
        XCTAssertEqual(Interpolate.atTime(points, time: 10), 100)
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(Interpolate.atTime([], time: 1))
    }
}
