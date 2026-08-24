import CoreGraphics
import Foundation

/// A single cubic Bézier segment between two samples.
public struct CubicSegment: Equatable, Sendable {
    /// Segment start point.
    public var start: CGPoint
    /// First control point (near `start`).
    public var control1: CGPoint
    /// Second control point (near `end`).
    public var control2: CGPoint
    /// Segment end point.
    public var end: CGPoint

    /// Creates a cubic segment.
    public init(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }
}

/// Builds a smooth curve through a set of points using **Fritsch–Carlson**
/// monotone cubic interpolation. Unlike a plain Catmull–Rom spline this never
/// overshoots between samples, so a rising line never dips and a value never
/// appears to exceed a local extremum.
public enum PathBuilder {
    /// Computes the monotone tangent (slope) at each input point.
    ///
    /// Points must be strictly increasing in `x`. Fewer than two points yields
    /// an empty result.
    public static func monotoneTangents(_ points: [CGPoint]) -> [CGFloat] {
        let n = points.count
        guard n >= 2 else { return [] }

        // Secant slopes between consecutive points.
        var delta = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            let dx = points[i + 1].x - points[i].x
            delta[i] = dx == 0 ? 0 : (points[i + 1].y - points[i].y) / dx
        }

        // Initial tangents: one-sided at the ends, averaged in the interior.
        var m = [CGFloat](repeating: 0, count: n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        for i in 1..<(n - 1) {
            if delta[i - 1] * delta[i] <= 0 {
                // Local extremum: flatten to preserve monotonicity.
                m[i] = 0
            } else {
                m[i] = (delta[i - 1] + delta[i]) / 2
            }
        }

        // Fritsch–Carlson constraint: keep (alpha, beta) inside a circle of
        // radius 3 to guarantee monotonicity.
        for i in 0..<(n - 1) {
            if delta[i] == 0 {
                m[i] = 0
                m[i + 1] = 0
                continue
            }
            let alpha = m[i] / delta[i]
            let beta = m[i + 1] / delta[i]
            let s = alpha * alpha + beta * beta
            if s > 9 {
                let tau = 3 / (s.squareRoot())
                m[i] = tau * alpha * delta[i]
                m[i + 1] = tau * beta * delta[i]
            }
        }
        return m
    }

    /// Builds cubic Bézier segments for a monotone curve through `points`.
    ///
    /// Each segment's control points sit one third of the way along the
    /// x-interval, offset vertically by the local tangent — the standard Hermite
    /// → Bézier conversion.
    public static func monotoneSegments(_ points: [CGPoint]) -> [CubicSegment] {
        let n = points.count
        guard n >= 2 else { return [] }
        let m = monotoneTangents(points)
        var segments = [CubicSegment]()
        segments.reserveCapacity(n - 1)
        for i in 0..<(n - 1) {
            let p0 = points[i]
            let p1 = points[i + 1]
            let h = p1.x - p0.x
            let c1 = CGPoint(x: p0.x + h / 3, y: p0.y + m[i] * h / 3)
            let c2 = CGPoint(x: p1.x - h / 3, y: p1.y - m[i + 1] * h / 3)
            segments.append(CubicSegment(start: p0, control1: c1, control2: c2, end: p1))
        }
        return segments
    }
}
