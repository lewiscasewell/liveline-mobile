package com.liveline.core

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.round

/**
 * Grid interval selection for the value axis, matching web liveline's
 * `pickInterval` (a TradingView-style cycling-divisor search) with hysteresis:
 * once an interval is chosen it is kept until its on-screen spacing falls outside
 * `[0.5×, 4×]` of the minimum gap, which stops the grid flickering as the domain
 * eases.
 */
object Ticks {
    /**
     * Picks the coarse interval.
     * @param valRange The visible value span.
     * @param pxPerUnit Pixels per value unit (`chartH / valRange`).
     * @param minGap Minimum pixel gap between coarse labels (liveline uses 36).
     * @param prev The previously chosen interval, for hysteresis (0 if none).
     */
    fun pickInterval(valRange: Double, pxPerUnit: Double, minGap: Double, prev: Double): Double {
        if (prev > 0) {
            val px = prev * pxPerUnit
            if (px >= minGap * 0.5 && px <= minGap * 4) return prev
        }

        val divisorSets = listOf(
            doubleArrayOf(2.0, 2.5, 2.0),
            doubleArrayOf(2.0, 2.0, 2.5),
            doubleArrayOf(2.5, 2.0, 2.0),
        )
        var best = Double.POSITIVE_INFINITY
        for (divs in divisorSets) {
            if (valRange <= 0) continue
            var span = 10.0.pow(ceil(log10(valRange)))
            var i = 0
            while (span / divs[i % 3] * pxPerUnit >= minGap) {
                span /= divs[i % 3]
                i += 1
            }
            if (span < best) best = span
        }
        return if (best == Double.POSITIVE_INFINITY) valRange / 5 else best
    }

    /** Float-safe check that [value] is an integer multiple of [interval]. */
    fun divisible(value: Double, interval: Double): Boolean {
        if (interval == 0.0) return false
        val ratio = value / interval
        return abs(ratio - round(ratio)) < 0.01
    }
}
