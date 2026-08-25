package com.liveline.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Downsampling for dense series.
 *
 * - [minMax] — pixel-accurate: for each screen column it keeps the local
 *   minimum and maximum, so spikes are never lost. Best when there are far more
 *   samples than pixels.
 * - [lttb] — Largest-Triangle-Three-Buckets: keeps the points that best preserve
 *   the *shape* of the line for a target sample count.
 *
 * Both return the **retained indices** into the input, in ascending order.
 */
object Decimate {
    /**
     * Min/max decimation to roughly [targetWidth] columns. Returns all indices
     * when not meaningfully denser than the target; the first and last indices
     * are always retained.
     */
    fun minMax(values: DoubleArray, targetWidth: Int): List<Int> {
        val n = values.size
        if (n == 0) return emptyList()
        if (targetWidth <= 0 || n <= targetWidth * 2) return (0 until n).toList()

        val indices = ArrayList<Int>(targetWidth * 2 + 2)
        val bucket = n.toDouble() / targetWidth
        for (col in 0 until targetWidth) {
            val lo = (col * bucket).toInt()
            val hi = min(((col + 1) * bucket).toInt(), n)
            if (lo >= hi) continue
            var minI = lo
            var maxI = lo
            for (i in lo until hi) {
                if (values[i] < values[minI]) minI = i
                if (values[i] > values[maxI]) maxI = i
            }
            val a = min(minI, maxI)
            val b = max(minI, maxI)
            if (indices.lastOrNull() != a) indices.add(a)
            if (b != a) indices.add(b)
        }
        if (indices.firstOrNull() != 0) indices.add(0, 0)
        if (indices.lastOrNull() != n - 1) indices.add(n - 1)
        return indices
    }

    /**
     * Largest-Triangle-Three-Buckets downsampling to [threshold] points. Returns
     * all indices when [threshold] is not smaller than the input, and `[0, n-1]`
     * when `threshold <= 2`. The first and last indices are always retained.
     */
    fun lttb(points: List<Point>, threshold: Int): List<Int> {
        val n = points.size
        if (n <= 2) return (0 until n).toList()
        if (threshold >= n) return (0 until n).toList()
        if (threshold <= 2) return listOf(0, n - 1)

        val sampled = ArrayList<Int>(threshold)
        sampled.add(0)

        val bucketSize = (n - 2).toDouble() / (threshold - 2)
        var a = 0

        for (i in 0 until (threshold - 2)) {
            // Average point of the next bucket.
            val avgStart = ((i + 1) * bucketSize).toInt() + 1
            val avgEnd = min(((i + 2) * bucketSize).toInt() + 1, n)
            var avgX = 0.0
            var avgY = 0.0
            val avgCount = max(avgEnd - avgStart, 1)
            for (j in avgStart until max(avgEnd, avgStart)) {
                avgX += points[j].x
                avgY += points[j].y
            }
            avgX /= avgCount
            avgY /= avgCount

            // Point in the current bucket forming the largest triangle with `a`
            // and the next bucket's average.
            val rangeStart = (i * bucketSize).toInt() + 1
            val rangeEnd = min(((i + 1) * bucketSize).toInt() + 1, n)
            val ax = points[a].x
            val ay = points[a].y
            var maxArea = -1.0
            var chosen = rangeStart
            var j = rangeStart
            while (j < max(rangeEnd, rangeStart + 1) && j < n) {
                val area = abs(
                    (ax - avgX) * (points[j].y - ay) - (ax - points[j].x) * (avgY - ay)
                ) * 0.5
                if (area > maxArea) {
                    maxArea = area
                    chosen = j
                }
                j++
            }
            sampled.add(chosen)
            a = chosen
        }

        sampled.add(n - 1)
        return sampled
    }
}
