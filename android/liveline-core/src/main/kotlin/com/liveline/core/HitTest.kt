package com.liveline.core

/**
 * Binary search for the sample nearest a scrub position. The render loop maps a
 * touch x back to a time via [Scale.invert] and asks which sample the finger is
 * over.
 */
object HitTest {
    /**
     * Returns the index of the sample whose time is closest to [x]. [times] must
     * be sorted ascending; ties resolve to the earlier index. Returns `null`
     * only for an empty array.
     */
    fun nearest(times: List<Double>, x: Double): Int? {
        if (times.isEmpty()) return null
        if (x <= times[0]) return 0
        val lastIndex = times.size - 1
        if (x >= times[lastIndex]) return lastIndex

        var lo = 0
        var hi = lastIndex
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            val v = times[mid]
            if (v == x) return mid
            if (v < x) lo = mid + 1 else hi = mid - 1
        }
        // `hi` is the last index below x, `lo` the first above.
        val before = hi
        val after = lo
        if (before < 0) return after
        if (after > lastIndex) return before
        return if (x - times[before] <= times[after] - x) before else after
    }
}
