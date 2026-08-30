package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class InterpolateTest {
    private val points = listOf(
        LivelinePoint(time = 0.0, value = 0.0),
        LivelinePoint(time = 10.0, value = 100.0),
        LivelinePoint(time = 20.0, value = 50.0),
    )

    @Test
    fun interpolatesMidSegment() {
        assertEquals(50.0, Interpolate.atTime(points, 5.0) ?: Double.NaN, 1e-9)
        assertEquals(75.0, Interpolate.atTime(points, 15.0) ?: Double.NaN, 1e-9)
    }

    @Test
    fun clampsBelowAndAbove() {
        assertEquals(0.0, Interpolate.atTime(points, -5.0))
        assertEquals(50.0, Interpolate.atTime(points, 100.0))
    }

    @Test
    fun exactVertices() {
        assertEquals(100.0, Interpolate.atTime(points, 10.0))
    }

    @Test
    fun emptyReturnsNull() {
        assertNull(Interpolate.atTime(emptyList(), 1.0))
    }
}
