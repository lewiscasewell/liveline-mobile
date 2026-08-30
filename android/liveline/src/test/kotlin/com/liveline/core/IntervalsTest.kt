package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals

class IntervalsTest {
    @Test
    fun matchesReferenceTable() {
        assertEquals(2.0, Intervals.niceTimeInterval(10.0))
        assertEquals(5.0, Intervals.niceTimeInterval(30.0))
        assertEquals(10.0, Intervals.niceTimeInterval(60.0))
        assertEquals(30.0, Intervals.niceTimeInterval(300.0))
        assertEquals(600.0, Intervals.niceTimeInterval(3600.0))
        assertEquals(7200.0, Intervals.niceTimeInterval(86400.0))
    }

    @Test
    fun beyondWeekIsWeek() {
        assertEquals(604800.0, Intervals.niceTimeInterval(2_000_000.0))
    }
}
