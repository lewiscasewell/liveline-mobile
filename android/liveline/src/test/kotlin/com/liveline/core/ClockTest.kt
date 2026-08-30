package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ClockTest {
    @Test
    fun lerpMovesTowardTarget() {
        val next = Clock.lerp(current = 0.0, target = 10.0, speed = 0.1)
        assertTrue(next > 0)
        assertTrue(next < 10)
    }

    @Test
    fun oneFrameEqualsSpeedFraction() {
        // At exactly one 60fps frame, the factor is `speed`.
        val next = Clock.lerp(current = 0.0, target = 100.0, speed = 0.25, dt = Clock.FRAME_MS)
        assertEquals(25.0, next, 1e-9)
    }

    @Test
    fun frameRateIndependence() {
        // One big step vs many small steps over the same total time agree.
        val total = 100.0 // ms
        val oneStep = Clock.lerp(current = 0.0, target = 1.0, speed = 0.2, dt = total)

        var v = 0.0
        val steps = 600
        repeat(steps) {
            v = Clock.lerp(current = v, target = 1.0, speed = 0.2, dt = total / steps)
        }
        assertEquals(oneStep, v, 1e-4)
    }
}
