import CoreGraphics
import XCTest

@testable import LivelineKit

final class PathBuilderTests: XCTestCase {
    func testTangentsOnStraightLineAreSlope() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 2), CGPoint(x: 2, y: 4)]
        let m = PathBuilder.monotoneTangents(points)
        XCTAssertEqual(m.count, 3)
        for t in m { XCTAssertEqual(t, 2, accuracy: 1e-12) }
    }

    func testControlPointsLieOnStraightLine() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 3)]
        let segs = PathBuilder.monotoneSegments(points)
        XCTAssertEqual(segs.count, 1)
        let seg = segs[0]
        // On y = x, both controls lie on the line.
        XCTAssertEqual(seg.control1.y, seg.control1.x, accuracy: 1e-12)
        XCTAssertEqual(seg.control2.y, seg.control2.x, accuracy: 1e-12)
    }

    func testPeakTangentIsFlat() {
        // A local maximum must have a zero tangent to prevent overshoot.
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 0)]
        let m = PathBuilder.monotoneTangents(points)
        XCTAssertEqual(m[1], 0, accuracy: 1e-12)
    }

    func testNoOvershootOnMonotoneData() {
        // Control-point y must stay within each rising segment's endpoints.
        let ys: [CGFloat] = [0, 0.1, 0.15, 5, 5.2, 5.3, 9]
        let points = ys.enumerated().map { CGPoint(x: CGFloat($0.offset), y: $0.element) }
        for seg in PathBuilder.monotoneSegments(points) {
            let lo = min(seg.start.y, seg.end.y)
            let hi = max(seg.start.y, seg.end.y)
            XCTAssertGreaterThanOrEqual(seg.control1.y, lo - 1e-9)
            XCTAssertLessThanOrEqual(seg.control1.y, hi + 1e-9)
            XCTAssertGreaterThanOrEqual(seg.control2.y, lo - 1e-9)
            XCTAssertLessThanOrEqual(seg.control2.y, hi + 1e-9)
        }
    }

    func testEmptyForTooFewPoints() {
        XCTAssertTrue(PathBuilder.monotoneSegments([]).isEmpty)
        XCTAssertTrue(PathBuilder.monotoneSegments([CGPoint(x: 0, y: 0)]).isEmpty)
    }
}
