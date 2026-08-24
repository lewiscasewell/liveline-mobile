import XCTest

@testable import LivelineKit

final class DomainTests: XCTestCase {
    func testFirstUpdateSnapsToTarget() {
        var domain = Domain()
        let target = AutoRange.Bounds(min: -1, max: 11)
        domain.update(target: target, speed: 0.08, dt: 16.67, chartH: 300)
        XCTAssertEqual(domain.minVal, -1, accuracy: 1e-12)
        XCTAssertEqual(domain.maxVal, 11, accuracy: 1e-12)
    }

    func testEasesTowardTarget() {
        var domain = Domain(minVal: 0, maxVal: 1)
        let target = AutoRange.Bounds(min: 0, max: 10)
        for _ in 0..<600 {
            domain.update(target: target, speed: 0.08, dt: 16.67, chartH: 300)
        }
        XCTAssertEqual(domain.minVal, 0, accuracy: 1e-6)
        XCTAssertEqual(domain.maxVal, 10, accuracy: 1e-6)
    }

    func testValRangeNeverZero() {
        let domain = Domain(minVal: 5, maxVal: 5)
        XCTAssertEqual(domain.valRange, 0.001, accuracy: 1e-12)
    }

    func testResetReSnaps() {
        var domain = Domain(minVal: 0, maxVal: 10)
        domain.reset()
        domain.update(target: AutoRange.Bounds(min: 100, max: 200), speed: 0.08, dt: 16.67, chartH: 300)
        XCTAssertEqual(domain.minVal, 100, accuracy: 1e-12)
        XCTAssertEqual(domain.maxVal, 200, accuracy: 1e-12)
    }

    func testAdaptiveSpeedFasterForSmallGaps() {
        let big = Domain.adaptiveSpeed(
            value: 100, displayValue: 0, displayMin: 0, displayMax: 100, base: 0.08)
        let small = Domain.adaptiveSpeed(
            value: 1, displayValue: 0, displayMin: 0, displayMax: 100, base: 0.08)
        XCTAssertLessThan(big, small)
        XCTAssertEqual(small, 0.08 + (1 - 0.01) * 0.2, accuracy: 1e-9)
    }
}
