package com.liveline.core

/**
 * Picks a nice time-axis tick interval in seconds for a given visible window,
 * extending web liveline's `niceTimeInterval` up through months and years so a
 * multi-timeframe chart (30 min → 4 years) labels sensibly.
 */
object Intervals {
    /** The tick spacing, in seconds, for a window of [windowSecs] seconds. */
    fun niceTimeInterval(windowSecs: Double): Double {
        val minute = 60.0
        val hour = 3600.0
        val day = 86400.0
        val week = 604800.0
        val month = 2_592_000.0 // 30 days
        val year = 31_536_000.0 // 365 days

        return when {
            windowSecs <= 15 -> 2.0
            windowSecs <= 30 -> 5.0
            windowSecs <= 60 -> 10.0
            windowSecs <= 120 -> 15.0
            windowSecs <= 300 -> 30.0
            windowSecs <= 600 -> minute
            windowSecs <= 1800 -> 5 * minute
            windowSecs <= hour -> 10 * minute
            windowSecs <= 4 * hour -> 30 * minute
            windowSecs <= 12 * hour -> hour
            windowSecs <= day -> 2 * hour
            windowSecs <= 3 * day -> 6 * hour
            windowSecs <= week -> day
            windowSecs <= month -> week
            windowSecs <= 3 * month -> 2 * week
            windowSecs <= year -> month
            windowSecs <= 2 * year -> 3 * month // quarters
            else -> year
        }
    }
}
