package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals

class MomentumDetectTest {
    private fun series(values: List<Double>): List<LivelinePoint> =
        values.mapIndexed { i, v -> LivelinePoint(time = i.toDouble(), value = v) }

    @Test
    fun tooFewPointsIsFlat() {
        assertEquals(Trend.FLAT, MomentumDetect.detect(series(listOf(1.0, 2.0, 3.0))))
    }

    @Test
    fun risingTailIsUp() {
        // Flat then a sharp rise in the last 5 points.
        assertEquals(
            Trend.UP,
            MomentumDetect.detect(series(listOf(10.0, 10.0, 10.0, 10.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0))),
        )
    }

    @Test
    fun fallingTailIsDown() {
        assertEquals(
            Trend.DOWN,
            MomentumDetect.detect(series(listOf(20.0, 20.0, 20.0, 20.0, 20.0, 18.0, 16.0, 14.0, 12.0, 10.0))),
        )
    }

    @Test
    fun steadyIsFlat() {
        assertEquals(Trend.FLAT, MomentumDetect.detect(series(List(10) { 5.0 })))
    }

    @Test
    fun oldMoveButSteadyNowIsFlat() {
        // Big move early, but the last 5 points are flat → flat (velocity is tail-based).
        val values = listOf(0.0, 50.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0)
        assertEquals(Trend.FLAT, MomentumDetect.detect(series(values)))
    }
}
