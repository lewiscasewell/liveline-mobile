package com.liveline.core

import kotlin.math.pow

/**
 * Frame-rate-independent exponential smoothing, matching web liveline's `lerp`.
 *
 * `speed` is the fraction of the remaining distance covered per 16.67 ms (one
 * 60 fps frame). The per-frame factor is `1 - (1 - speed)^(dt / 16.67)`, so the
 * result is invariant to the actual frame rate — a 60 fps and a 120 fps device
 * converge identically.
 */
object Clock {
    /** One 60 fps frame, in milliseconds. */
    const val FRAME_MS: Double = 16.67

    /**
     * Smooths [current] toward [target].
     *
     * @param current The current value.
     * @param target The value to approach.
     * @param speed Fraction approached per 16.67 ms frame (`0..1`).
     * @param dt Elapsed time since the last update, in milliseconds.
     */
    fun lerp(current: Double, target: Double, speed: Double, dt: Double = FRAME_MS): Double {
        val factor = 1 - (1 - speed).pow(dt / FRAME_MS)
        return current + (target - current) * factor
    }
}
