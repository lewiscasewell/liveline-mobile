import XCTest

@testable import LivelineKit

final class AutoRangeTests: XCTestCase {
    func testAddsMarginAroundData() {
        let b = AutoRange.compute(values: [0, 10], currentValue: 10)
        // raw range 10, margin 0.12 → [-1.2, 11.2]
        XCTAssertEqual(b.min, -1.2, accuracy: 1e-9)
        XCTAssertEqual(b.max, 11.2, accuracy: 1e-9)
    }

    func testFlatDataOpensMinimumWindow() {
        let b = AutoRange.compute(values: [5, 5, 5], currentValue: 5)
        // rawRange 0 → minRange fallback 0.4, centered on 5 → [4.8, 5.2]
        XCTAssertEqual(b.min, 4.8, accuracy: 1e-9)
        XCTAssertEqual(b.max, 5.2, accuracy: 1e-9)
    }

    func testIncludesCurrentValueBeyondData() {
        let b = AutoRange.compute(values: [0, 1], currentValue: 100)
        XCTAssertLessThanOrEqual(b.min, 0)
        XCTAssertGreaterThanOrEqual(b.max, 100)
    }

    func testIncludesReferenceLine() {
        let b = AutoRange.compute(values: [0, 10], currentValue: 5, referenceValue: 50)
        XCTAssertGreaterThanOrEqual(b.max, 50)
    }

    func testExaggerateTightensMargin() {
        let normal = AutoRange.compute(values: [0, 10], currentValue: 10, exaggerate: false)
        let exag = AutoRange.compute(values: [0, 10], currentValue: 10, exaggerate: true)
        XCTAssertLessThan(exag.max - exag.min, normal.max - normal.min)
    }
}
