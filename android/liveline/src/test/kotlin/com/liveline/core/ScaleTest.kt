package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals

class ScaleTest {
    @Test
    fun linearProjection() {
        val s = Scale(domainMin = 0.0, domainMax = 10.0, rangeMin = 0.0, rangeMax = 100.0)
        assertEquals(0.0, s.scale(0.0), 1e-12)
        assertEquals(50.0, s.scale(5.0), 1e-12)
        assertEquals(100.0, s.scale(10.0), 1e-12)
    }

    @Test
    fun invertRoundTrips() {
        val s = Scale(domainMin = -1.0, domainMax = 3.0, rangeMin = 20.0, rangeMax = 220.0)
        var x = -1.0
        while (x <= 3.0 + 1e-12) {
            assertEquals(x, s.invert(s.scale(x)), 1e-9)
            x += 0.25
        }
    }

    @Test
    fun invertedRange() {
        // Value up -> pixel down.
        val s = Scale(domainMin = 0.0, domainMax = 1.0, rangeMin = 300.0, rangeMax = 0.0)
        assertEquals(300.0, s.scale(0.0), 1e-12)
        assertEquals(0.0, s.scale(1.0), 1e-12)
        assertEquals(150.0, s.scale(0.5), 1e-12)
    }

    @Test
    fun degenerateDomain() {
        val s = Scale(domainMin = 5.0, domainMax = 5.0, rangeMin = 10.0, rangeMax = 90.0)
        assertEquals(10.0, s.scale(5.0), 1e-12)
        assertEquals(10.0, s.scale(100.0), 1e-12)
    }
}
