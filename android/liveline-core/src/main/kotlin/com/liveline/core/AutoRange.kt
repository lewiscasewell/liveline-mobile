package com.liveline.core

/**
 * Computes the target visible Y range from the data, matching web liveline's
 * `computeRange`. The range spans the visible values, the current live value and
 * an optional reference line, then adds a margin (or opens a minimum window when
 * the data is nearly flat). [exaggerate] tightens the margin so small movements
 * fill the chart height.
 */
object AutoRange {
    /** The computed target range. */
    data class Bounds(val min: Double, val max: Double)

    /**
     * Computes the target range.
     * @param values Visible sample values.
     * @param currentValue The current live value (always included).
     * @param referenceValue Optional reference-line value to keep in view.
     * @param exaggerate When `true`, use a tight margin.
     */
    fun compute(
        values: List<Double>,
        currentValue: Double,
        referenceValue: Double? = null,
        exaggerate: Boolean = false,
    ): Bounds {
        var targetMin = Double.POSITIVE_INFINITY
        var targetMax = Double.NEGATIVE_INFINITY

        for (v in values) {
            if (v < targetMin) targetMin = v
            if (v > targetMax) targetMax = v
        }
        if (currentValue < targetMin) targetMin = currentValue
        if (currentValue > targetMax) targetMax = currentValue
        if (referenceValue != null) {
            if (referenceValue < targetMin) targetMin = referenceValue
            if (referenceValue > targetMax) targetMax = referenceValue
        }

        // Guard against no data at all.
        if (!targetMin.isFinite() || !targetMax.isFinite()) {
            targetMin = currentValue - 0.5
            targetMax = currentValue + 0.5
        }

        val rawRange = targetMax - targetMin
        val marginFactor = if (exaggerate) 0.01 else 0.12
        val scaled = rawRange * (if (exaggerate) 0.02 else 0.1)
        val minRange = if (scaled != 0.0) scaled else (if (exaggerate) 0.04 else 0.4)

        if (rawRange < minRange) {
            val mid = (targetMin + targetMax) / 2
            targetMin = mid - minRange / 2
            targetMax = mid + minRange / 2
        } else {
            val margin = rawRange * marginFactor
            targetMin -= margin
            targetMax += margin
        }

        return Bounds(targetMin, targetMax)
    }

    /**
     * Computes the target range for candle mode from OHLC lows/highs, matching
     * web liveline's `computeCandleRange`.
     */
    fun computeCandles(candles: List<LivelineCandle>): Bounds {
        var minV = Double.POSITIVE_INFINITY
        var maxV = Double.NEGATIVE_INFINITY
        for (c in candles) {
            if (c.low < minV) minV = c.low
            if (c.high > maxV) maxV = c.high
        }
        if (!minV.isFinite() || !maxV.isFinite()) return Bounds(99.0, 101.0)
        val range = maxV - minV
        val margin = range * 0.12
        val scaled = range * 0.1
        val minRange = if (scaled != 0.0) scaled else 0.4
        if (range < minRange) {
            val mid = (minV + maxV) / 2
            return Bounds(mid - minRange / 2, mid + minRange / 2)
        }
        return Bounds(minV - margin, maxV + margin)
    }
}
