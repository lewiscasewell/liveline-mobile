package com.liveline.core

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class TicksTest {
    @Test
    fun pickIntervalGivesReasonableSpacing() {
        val interval = Ticks.pickInterval(valRange = 100.0, pxPerUnit = 3.0, minGap = 36.0, prev = 0.0)
        assertTrue(interval * 3 >= 36)
        assertTrue(interval <= 100)
    }

    @Test
    fun hysteresisKeepsPreviousInterval() {
        val kept = Ticks.pickInterval(valRange = 105.0, pxPerUnit = 3.0, minGap = 36.0, prev = 20.0)
        assertEquals(20.0, kept, 1e-12)
    }

    @Test
    fun hysteresisReleasesWhenTooCramped() {
        val released = Ticks.pickInterval(valRange = 100.0, pxPerUnit = 3.0, minGap = 36.0, prev = 5.0)
        assertNotEquals(5.0, released)
    }

    @Test
    fun divisible() {
        assertTrue(Ticks.divisible(40.0, 20.0))
        assertTrue(Ticks.divisible(0.0, 20.0))
        assertTrue(!Ticks.divisible(30.0, 20.0))
    }

    @Test
    fun niceRoundNumbers() {
        val interval = Ticks.pickInterval(valRange = 1000.0, pxPerUnit = 0.3, minGap = 36.0, prev = 0.0)
        val normalized = interval / 10.0.pow(floor(log10(interval)))
        assertTrue(
            listOf(1.0, 2.0, 2.5, 5.0).any { abs(it - normalized) < 0.01 },
            "interval $interval normalized $normalized is not a nice number",
        )
    }
}
