import XCTest

@testable import LivelineKit

final class ScaleTests: XCTestCase {
    func testLinearProjection() {
        let s = Scale(domainMin: 0, domainMax: 10, rangeMin: 0, rangeMax: 100)
        XCTAssertEqual(s.scale(0), 0, accuracy: 1e-12)
        XCTAssertEqual(s.scale(5), 50, accuracy: 1e-12)
        XCTAssertEqual(s.scale(10), 100, accuracy: 1e-12)
    }

    func testInvertRoundTrips() {
        let s = Scale(domainMin: -1, domainMax: 3, rangeMin: 20, rangeMax: 220)
        for x in stride(from: -1.0, through: 3.0, by: 0.25) {
            XCTAssertEqual(s.invert(s.scale(x)), x, accuracy: 1e-9)
        }
    }

    func testInvertedRange() {
        // Value up -> pixel down.
        let s = Scale(domainMin: 0, domainMax: 1, rangeMin: 300, rangeMax: 0)
        XCTAssertEqual(s.scale(0), 300, accuracy: 1e-12)
        XCTAssertEqual(s.scale(1), 0, accuracy: 1e-12)
        XCTAssertEqual(s.scale(0.5), 150, accuracy: 1e-12)
    }

    func testDegenerateDomain() {
        let s = Scale(domainMin: 5, domainMax: 5, rangeMin: 10, rangeMax: 90)
        XCTAssertEqual(s.scale(5), 10)
        XCTAssertEqual(s.scale(100), 10)
    }
}
