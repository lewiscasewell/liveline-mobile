import XCTest

@testable import LivelineKit

final class TicksTests: XCTestCase {
    func testPickIntervalGivesReasonableSpacing() {
        // 100-unit range over 300px, min gap 36px → interval whose pixel
        // spacing is >= 36.
        let interval = Ticks.pickInterval(valRange: 100, pxPerUnit: 3, minGap: 36, prev: 0)
        XCTAssertGreaterThanOrEqual(interval * 3, 36)
        // And not absurdly coarse (fewer than ~2 lines).
        XCTAssertLessThanOrEqual(interval, 100)
    }

    func testHysteresisKeepsPreviousInterval() {
        // prev interval 20 with spacing 20*3=60px is within [0.5,4]×36 → kept.
        let kept = Ticks.pickInterval(valRange: 105, pxPerUnit: 3, minGap: 36, prev: 20)
        XCTAssertEqual(kept, 20, accuracy: 1e-12)
    }

    func testHysteresisReleasesWhenTooCramped() {
        // prev interval 5 with spacing 5*3=15px < 0.5*36=18 → released.
        let released = Ticks.pickInterval(valRange: 100, pxPerUnit: 3, minGap: 36, prev: 5)
        XCTAssertNotEqual(released, 5)
    }

    func testDivisible() {
        XCTAssertTrue(Ticks.divisible(40, by: 20))
        XCTAssertTrue(Ticks.divisible(0, by: 20))
        XCTAssertFalse(Ticks.divisible(30, by: 20))
    }

    func testNiceRoundNumbers() {
        // The chosen interval should be a 1/2/2.5/5 × 10ⁿ style value.
        let interval = Ticks.pickInterval(valRange: 1000, pxPerUnit: 0.3, minGap: 36, prev: 0)
        let normalized = interval / pow(10, (log10(interval)).rounded(.down))
        XCTAssertTrue(
            [1, 2, 2.5, 5].contains { abs($0 - normalized) < 0.01 },
            "interval \(interval) normalized \(normalized) is not a nice number"
        )
    }
}
