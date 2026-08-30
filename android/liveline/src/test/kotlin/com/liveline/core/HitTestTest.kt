package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class HitTestTest {
    private val times = listOf(0.0, 1.0, 2.0, 3.0, 4.0, 5.0)

    @Test
    fun exactMatch() {
        assertEquals(3, HitTest.nearest(times, 3.0))
    }

    @Test
    fun nearestRoundsToCloser() {
        assertEquals(2, HitTest.nearest(times, 2.4))
        assertEquals(3, HitTest.nearest(times, 2.6))
    }

    @Test
    fun tieResolvesToEarlier() {
        assertEquals(2, HitTest.nearest(times, 2.5))
    }

    @Test
    fun belowRangeClampsToFirst() {
        assertEquals(0, HitTest.nearest(times, -10.0))
    }

    @Test
    fun aboveRangeClampsToLast() {
        assertEquals(5, HitTest.nearest(times, 99.0))
    }

    @Test
    fun emptyReturnsNull() {
        assertNull(HitTest.nearest(emptyList(), 1.0))
    }

    @Test
    fun unevenSpacing() {
        val uneven = listOf(0.0, 10.0, 12.0, 100.0)
        assertEquals(2, HitTest.nearest(uneven, 11.4))
        assertEquals(1, HitTest.nearest(uneven, 6.0))
    }
}
