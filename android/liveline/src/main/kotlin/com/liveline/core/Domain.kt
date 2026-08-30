package com.liveline.core

import kotlin.math.abs
import kotlin.math.min

/**
 * Holds the eased visible Y domain and advances it toward a target each frame,
 * matching web liveline's `updateRange` (steady-state path). The target comes
 * from [AutoRange.compute]; each frame the visible bounds lerp toward it with an
 * adaptive speed, then snap when within half a pixel. There is deliberately
 * **no hysteresis** — that is not how the reference library behaves.
 */
class Domain private constructor(
    minVal: Double,
    maxVal: Double,
    private var inited: Boolean,
) {
    /** Current visible lower bound. */
    var minVal: Double = minVal
        private set
    /** Current visible upper bound. */
    var maxVal: Double = maxVal
        private set

    /** Creates an uninitialised domain; the first [update] snaps to the target. */
    constructor() : this(0.0, 1.0, false)

    /** The current visible span (never zero). */
    val valRange: Double get() = if ((maxVal - minVal) == 0.0) 0.001 else (maxVal - minVal)

    /**
     * Advances the domain by one frame.
     * @param target The target bounds from [AutoRange].
     * @param speed Adaptive lerp speed (per 16.67 ms frame).
     * @param dt Elapsed time since the last update, in milliseconds.
     * @param chartH Chart height in points, for the sub-pixel snap threshold.
     */
    fun update(target: AutoRange.Bounds, speed: Double, dt: Double, chartH: Double) {
        if (!inited) {
            minVal = target.min
            maxVal = target.max
            inited = true
            return
        }
        val curRange = maxVal - minVal
        minVal = Clock.lerp(minVal, target.min, speed, dt)
        maxVal = Clock.lerp(maxVal, target.max, speed, dt)
        val pxThreshold = if (chartH != 0.0) 0.5 * curRange / chartH else 0.001
        val threshold = if (pxThreshold == 0.0) 0.001 else pxThreshold
        if (abs(minVal - target.min) < threshold) minVal = target.min
        if (abs(maxVal - target.max) < threshold) maxVal = target.max
    }

    /** Resets the domain so the next update snaps to its target. */
    fun reset() {
        inited = false
    }

    /**
     * A [Scale] mapping this domain onto a pixel range. The range is usually
     * inverted ([rangeMin] at the bottom) so larger values appear higher.
     */
    fun scale(rangeMin: Double, rangeMax: Double): Scale =
        Scale(domainMin = minVal, domainMax = maxVal, rangeMin = rangeMin, rangeMax = rangeMax)

    companion object {
        /** Creates a domain seeded with explicit bounds (mainly for tests). */
        fun seeded(minVal: Double, maxVal: Double): Domain = Domain(minVal, maxVal, true)

        /**
         * The adaptive lerp speed used for both the value and the range, matching
         * liveline's `computeAdaptiveSpeed`: slower for big jumps, faster for small
         * ticks. [base] is `lerpSpeed` (default 0.08); the boost is up to `+0.2`.
         */
        fun adaptiveSpeed(
            value: Double,
            displayValue: Double,
            displayMin: Double,
            displayMax: Double,
            base: Double,
            boost: Double = 0.2,
        ): Double {
            val valGap = abs(value - displayValue)
            val prevRange = if ((displayMax - displayMin) == 0.0) 1.0 else (displayMax - displayMin)
            val gapRatio = min(valGap / prevRange, 1.0)
            return base + (1 - gapRatio) * boost
        }
    }
}
