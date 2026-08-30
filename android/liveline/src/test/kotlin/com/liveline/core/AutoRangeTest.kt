package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AutoRangeTest {
    @Test
    fun addsMarginAroundData() {
        val b = AutoRange.compute(values = listOf(0.0, 10.0), currentValue = 10.0)
        // raw range 10, margin 0.12 → [-1.2, 11.2]
        assertEquals(-1.2, b.min, 1e-9)
        assertEquals(11.2, b.max, 1e-9)
    }

    @Test
    fun flatDataOpensMinimumWindow() {
        val b = AutoRange.compute(values = listOf(5.0, 5.0, 5.0), currentValue = 5.0)
        // rawRange 0 → minRange fallback 0.4, centered on 5 → [4.8, 5.2]
        assertEquals(4.8, b.min, 1e-9)
        assertEquals(5.2, b.max, 1e-9)
    }

    @Test
    fun includesCurrentValueBeyondData() {
        val b = AutoRange.compute(values = listOf(0.0, 1.0), currentValue = 100.0)
        assertTrue(b.min <= 0)
        assertTrue(b.max >= 100)
    }

    @Test
    fun includesReferenceLine() {
        val b = AutoRange.compute(values = listOf(0.0, 10.0), currentValue = 5.0, referenceValue = 50.0)
        assertTrue(b.max >= 50)
    }

    @Test
    fun exaggerateTightensMargin() {
        val normal = AutoRange.compute(values = listOf(0.0, 10.0), currentValue = 10.0, exaggerate = false)
        val exag = AutoRange.compute(values = listOf(0.0, 10.0), currentValue = 10.0, exaggerate = true)
        assertTrue(exag.max - exag.min < normal.max - normal.min)
    }
}
