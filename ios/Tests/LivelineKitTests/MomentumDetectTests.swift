import XCTest

@testable import LivelineKit

final class MomentumDetectTests: XCTestCase {
    private func series(_ values: [Double]) -> [LivelinePoint] {
        values.enumerated().map { LivelinePoint(time: Double($0.offset), value: $0.element) }
    }

    func testTooFewPointsIsFlat() {
        XCTAssertEqual(MomentumDetect.detect(series([1, 2, 3])), .flat)
    }

    func testRisingTailIsUp() {
        // Flat then a sharp rise in the last 5 points.
        XCTAssertEqual(MomentumDetect.detect(series([10, 10, 10, 10, 10, 12, 14, 16, 18, 20])), .up)
    }

    func testFallingTailIsDown() {
        XCTAssertEqual(MomentumDetect.detect(series([20, 20, 20, 20, 20, 18, 16, 14, 12, 10])), .down)
    }

    func testSteadyIsFlat() {
        XCTAssertEqual(MomentumDetect.detect(series(Array(repeating: 5, count: 10))), .flat)
    }

    func testOldMoveButSteadyNowIsFlat() {
        // Big move early, but the last 5 points are flat → flat (velocity is tail-based).
        let values = [0.0, 50, 100, 100, 100, 100, 100, 100, 100, 100]
        XCTAssertEqual(MomentumDetect.detect(series(values)), .flat)
    }
}
