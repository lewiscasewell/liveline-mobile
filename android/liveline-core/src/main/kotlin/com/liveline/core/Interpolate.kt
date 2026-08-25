package com.liveline.core

/**
 * Linear interpolation of a series at an arbitrary time, matching web liveline's
 * `interpolateAtTime`. Used to read the scrub value at the crosshair. Points
 * must be ascending in `time`.
 */
object Interpolate {
    /**
     * Returns the interpolated value at [time], or `null` if the series is empty.
     * Times outside the series clamp to the nearest endpoint value.
     */
    fun atTime(points: List<LivelinePoint>, time: Double): Double? {
        if (points.isEmpty()) return null
        if (time <= points[0].time) return points[0].value
        val lastIndex = points.size - 1
        if (time >= points[lastIndex].time) return points[lastIndex].value

        var lo = 0
        var hi = lastIndex
        while (hi - lo > 1) {
            val mid = (lo + hi) ushr 1
            if (points[mid].time <= time) lo = mid else hi = mid
        }

        val p1 = points[lo]
        val p2 = points[hi]
        val dt = p2.time - p1.time
        if (dt == 0.0) return p1.value
        val t = (time - p1.time) / dt
        return p1.value + (p2.value - p1.value) * t
    }
}
