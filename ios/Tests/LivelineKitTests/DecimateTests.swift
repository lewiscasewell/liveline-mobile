import CoreGraphics
import XCTest

@testable import LivelineKit

final class DecimateTests: XCTestCase {
    func testMinMaxReturnsAllWhenSparse() {
        let values = [1.0, 2, 3, 4]
        XCTAssertEqual(Decimate.minMax(values: values, targetWidth: 10), [0, 1, 2, 3])
    }

    func testMinMaxRetainsEndpoints() {
        let values = (0..<200).map { Double($0) }
        let kept = Decimate.minMax(values: values, targetWidth: 20)
        XCTAssertEqual(kept.first, 0)
        XCTAssertEqual(kept.last, 199)
        // Indices are strictly ascending.
        XCTAssertEqual(kept, kept.sorted())
        XCTAssertEqual(Set(kept).count, kept.count)
    }

    func testMinMaxKeepsSpike() {
        var values = (0..<200).map { _ in 0.0 }
        values[123] = 999
        let kept = Decimate.minMax(values: values, targetWidth: 20)
        XCTAssertTrue(kept.contains(123), "the spike index must survive decimation")
    }

    func testLTTBReturnsThresholdCount() {
        let points = (0..<500).map { CGPoint(x: CGFloat($0), y: CGFloat(sin(Double($0) / 10))) }
        let kept = Decimate.lttb(points: points, threshold: 50)
        XCTAssertEqual(kept.count, 50)
        XCTAssertEqual(kept.first, 0)
        XCTAssertEqual(kept.last, 499)
        XCTAssertEqual(kept, kept.sorted())
    }

    func testLTTBSmallThreshold() {
        let points = (0..<100).map { CGPoint(x: CGFloat($0), y: 0) }
        XCTAssertEqual(Decimate.lttb(points: points, threshold: 2), [0, 99])
    }
}
