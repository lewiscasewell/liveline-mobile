package com.liveline.core

import kotlin.math.max
import kotlin.math.min
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PathBuilderTest {
    @Test
    fun tangentsOnStraightLineAreSlope() {
        val points = listOf(Point(0.0, 0.0), Point(1.0, 2.0), Point(2.0, 4.0))
        val m = PathBuilder.monotoneTangents(points)
        assertEquals(3, m.size)
        for (t in m) assertEquals(2.0, t, 1e-12)
    }

    @Test
    fun controlPointsLieOnStraightLine() {
        val points = listOf(Point(0.0, 0.0), Point(3.0, 3.0))
        val segs = PathBuilder.monotoneSegments(points)
        assertEquals(1, segs.size)
        val seg = segs[0]
        // On y = x, both controls lie on the line.
        assertEquals(seg.control1.x, seg.control1.y, 1e-12)
        assertEquals(seg.control2.x, seg.control2.y, 1e-12)
    }

    @Test
    fun peakTangentIsFlat() {
        // A local maximum must have a zero tangent to prevent overshoot.
        val points = listOf(Point(0.0, 0.0), Point(1.0, 1.0), Point(2.0, 0.0))
        val m = PathBuilder.monotoneTangents(points)
        assertEquals(0.0, m[1], 1e-12)
    }

    @Test
    fun noOvershootOnMonotoneData() {
        val ys = listOf(0.0, 0.1, 0.15, 5.0, 5.2, 5.3, 9.0)
        val points = ys.mapIndexed { i, y -> Point(i.toDouble(), y) }
        for (seg in PathBuilder.monotoneSegments(points)) {
            val lo = min(seg.start.y, seg.end.y)
            val hi = max(seg.start.y, seg.end.y)
            assertTrue(seg.control1.y >= lo - 1e-9)
            assertTrue(seg.control1.y <= hi + 1e-9)
            assertTrue(seg.control2.y >= lo - 1e-9)
            assertTrue(seg.control2.y <= hi + 1e-9)
        }
    }

    @Test
    fun emptyForTooFewPoints() {
        assertTrue(PathBuilder.monotoneSegments(emptyList()).isEmpty())
        assertTrue(PathBuilder.monotoneSegments(listOf(Point(0.0, 0.0))).isEmpty())
    }
}
