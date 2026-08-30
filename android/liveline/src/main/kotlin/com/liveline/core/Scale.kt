package com.liveline.core

/**
 * A linear mapping from a `domain` interval onto a `range` interval, with its
 * inverse. Used for both axes: time → x-pixels, and value → y-pixels (where the
 * range is usually inverted, [rangeMin] at the bottom of the view).
 *
 * A degenerate domain ([domainMin] == [domainMax]) maps everything to [rangeMin].
 */
data class Scale(
    val domainMin: Double,
    val domainMax: Double,
    val rangeMin: Double,
    val rangeMax: Double,
) {
    /** Projects a domain value into the range. */
    fun scale(x: Double): Double {
        val d = domainMax - domainMin
        if (d == 0.0) return rangeMin
        val t = (x - domainMin) / d
        return rangeMin + t * (rangeMax - rangeMin)
    }

    /** Maps a range value back into the domain. */
    fun invert(y: Double): Double {
        val r = rangeMax - rangeMin
        if (r == 0.0) return domainMin
        val t = (y - rangeMin) / r
        return domainMin + t * (domainMax - domainMin)
    }
}
