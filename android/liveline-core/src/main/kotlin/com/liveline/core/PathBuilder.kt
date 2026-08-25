package com.liveline.core

import kotlin.math.sqrt

/** A single cubic Bézier segment between two samples. */
data class CubicSegment(
    val start: Point,
    val control1: Point,
    val control2: Point,
    val end: Point,
)

/**
 * Builds a smooth curve through a set of points using **Fritsch–Carlson**
 * monotone cubic interpolation. Unlike a plain Catmull–Rom spline this never
 * overshoots between samples, so a rising line never dips and a value never
 * appears to exceed a local extremum.
 */
object PathBuilder {
    /**
     * Computes the monotone tangent (slope) at each input point. Points must be
     * strictly increasing in `x`; fewer than two points yields an empty result.
     */
    fun monotoneTangents(points: List<Point>): DoubleArray {
        val n = points.size
        if (n < 2) return DoubleArray(0)

        // Secant slopes between consecutive points.
        val delta = DoubleArray(n - 1)
        for (i in 0 until n - 1) {
            val dx = points[i + 1].x - points[i].x
            delta[i] = if (dx == 0.0) 0.0 else (points[i + 1].y - points[i].y) / dx
        }

        // Initial tangents: one-sided at the ends, averaged in the interior.
        val m = DoubleArray(n)
        m[0] = delta[0]
        m[n - 1] = delta[n - 2]
        for (i in 1 until n - 1) {
            m[i] = if (delta[i - 1] * delta[i] <= 0.0) {
                // Local extremum: flatten to preserve monotonicity.
                0.0
            } else {
                (delta[i - 1] + delta[i]) / 2
            }
        }

        // Fritsch–Carlson constraint: keep (alpha, beta) inside a circle of
        // radius 3 to guarantee monotonicity.
        for (i in 0 until n - 1) {
            if (delta[i] == 0.0) {
                m[i] = 0.0
                m[i + 1] = 0.0
                continue
            }
            val alpha = m[i] / delta[i]
            val beta = m[i + 1] / delta[i]
            val s = alpha * alpha + beta * beta
            if (s > 9) {
                val tau = 3 / sqrt(s)
                m[i] = tau * alpha * delta[i]
                m[i + 1] = tau * beta * delta[i]
            }
        }
        return m
    }

    /**
     * Builds cubic Bézier segments for a monotone curve through [points]. Each
     * segment's control points sit one third of the way along the x-interval,
     * offset vertically by the local tangent (Hermite → Bézier).
     */
    fun monotoneSegments(points: List<Point>): List<CubicSegment> {
        val n = points.size
        if (n < 2) return emptyList()
        val m = monotoneTangents(points)
        val segments = ArrayList<CubicSegment>(n - 1)
        for (i in 0 until n - 1) {
            val p0 = points[i]
            val p1 = points[i + 1]
            val h = p1.x - p0.x
            val c1 = Point(p0.x + h / 3, p0.y + m[i] * h / 3)
            val c2 = Point(p1.x - h / 3, p1.y - m[i + 1] * h / 3)
            segments.add(CubicSegment(p0, c1, c2, p1))
        }
        return segments
    }
}
