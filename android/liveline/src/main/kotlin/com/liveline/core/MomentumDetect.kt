package com.liveline.core

import kotlin.math.max

/**
 * Auto-detects the line's [Trend] from recent samples, matching web liveline's
 * `detectMomentum`.
 *
 * Only triggers during active movement: the threshold is a fraction of the
 * full-lookback range, but the velocity is measured over just the last few
 * points, so a line that drifted long ago but is now steady reads as `flat`.
 */
object MomentumDetect {
    /**
     * Detects the trend.
     * @param points The series (ascending in time).
     * @param lookback How many trailing points define the range (default 20).
     */
    fun detect(points: List<LivelinePoint>, lookback: Int = 20): Trend {
        if (points.size < 5) return Trend.FLAT
        val start = max(0, points.size - lookback)

        var minV = Double.POSITIVE_INFINITY
        var maxV = Double.NEGATIVE_INFINITY
        for (i in start until points.size) {
            val v = points[i].value
            if (v < minV) minV = v
            if (v > maxV) maxV = v
        }
        val range = maxV - minV
        if (range == 0.0) return Trend.FLAT

        val tailStart = max(start, points.size - 5)
        val first = points[tailStart].value
        val last = points[points.size - 1].value
        val delta = last - first
        val threshold = range * 0.12

        return when {
            delta > threshold -> Trend.UP
            delta < -threshold -> Trend.DOWN
            else -> Trend.FLAT
        }
    }
}
