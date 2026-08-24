import XCTest

@testable import LivelineKit

final class ClockTests: XCTestCase {
    func testLerpMovesTowardTarget() {
        let next = Clock.lerp(current: 0, target: 10, speed: 0.1)
        XCTAssertGreaterThan(next, 0)
        XCTAssertLessThan(next, 10)
    }

    func testOneFrameEqualsSpeedFraction() {
        // At exactly one 60fps frame, the factor is `speed`.
        let next = Clock.lerp(current: 0, target: 100, speed: 0.25, dt: Clock.frameMs)
        XCTAssertEqual(next, 25, accuracy: 1e-9)
    }

    func testFrameRateIndependence() {
        // One big step vs many small steps over the same total time agree.
        let total = 100.0  // ms
        let oneStep = Clock.lerp(current: 0, target: 1, speed: 0.2, dt: total)

        var v = 0.0
        let steps = 600
        for _ in 0..<steps {
            v = Clock.lerp(current: v, target: 1, speed: 0.2, dt: total / Double(steps))
        }
        XCTAssertEqual(oneStep, v, accuracy: 1e-4)
    }
}
