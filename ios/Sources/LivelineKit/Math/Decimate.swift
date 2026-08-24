import CoreGraphics
import Foundation

/// Downsampling for dense series. Two strategies:
///
/// - ``minMax(values:targetWidth:)`` — pixel-accurate: for each screen column it
///   keeps the local minimum and maximum, so spikes are never lost. Best when
///   there are far more samples than pixels.
/// - ``lttb(points:threshold:)`` — Largest-Triangle-Three-Buckets: keeps the
///   points that best preserve the *shape* of the line for a target sample
///   count. Best for a faithful thumbnail-style reduction.
///
/// Both return the **retained indices** into the input, in ascending order, so
/// the caller can look up the original samples.
public enum Decimate {
    /// Min/max decimation to roughly `targetWidth` columns.
    ///
    /// Returns all indices when the series is not meaningfully denser than the
    /// target. The first and last indices are always retained.
    public static func minMax(values: [Double], targetWidth: Int) -> [Int] {
        let n = values.count
        guard n > 0 else { return [] }
        guard targetWidth > 0, n > targetWidth * 2 else { return Array(0..<n) }

        var indices = [Int]()
        indices.reserveCapacity(targetWidth * 2 + 2)
        let bucket = Double(n) / Double(targetWidth)
        for col in 0..<targetWidth {
            let lo = Int(Double(col) * bucket)
            let hi = min(Int(Double(col + 1) * bucket), n)
            if lo >= hi { continue }
            var minI = lo
            var maxI = lo
            for i in lo..<hi {
                if values[i] < values[minI] { minI = i }
                if values[i] > values[maxI] { maxI = i }
            }
            let a = Swift.min(minI, maxI)
            let b = Swift.max(minI, maxI)
            if indices.last != a { indices.append(a) }
            if b != a { indices.append(b) }
        }
        if indices.first != 0 { indices.insert(0, at: 0) }
        if indices.last != n - 1 { indices.append(n - 1) }
        return indices
    }

    /// Largest-Triangle-Three-Buckets downsampling to `threshold` points.
    ///
    /// Returns all indices when `threshold` is not smaller than the input, and
    /// `[0, n-1]` when `threshold <= 2`. The first and last indices are always
    /// retained.
    public static func lttb(points: [CGPoint], threshold: Int) -> [Int] {
        let n = points.count
        guard n > 2 else { return Array(0..<n) }
        if threshold >= n { return Array(0..<n) }
        if threshold <= 2 { return [0, n - 1] }

        var sampled = [Int]()
        sampled.reserveCapacity(threshold)
        sampled.append(0)

        let bucketSize = Double(n - 2) / Double(threshold - 2)
        var a = 0

        for i in 0..<(threshold - 2) {
            // Average point of the next bucket.
            let avgStart = Int(Double(i + 1) * bucketSize) + 1
            let avgEnd = Swift.min(Int(Double(i + 2) * bucketSize) + 1, n)
            var avgX = 0.0
            var avgY = 0.0
            let avgCount = Swift.max(avgEnd - avgStart, 1)
            for j in avgStart..<Swift.max(avgEnd, avgStart) {
                avgX += Double(points[j].x)
                avgY += Double(points[j].y)
            }
            avgX /= Double(avgCount)
            avgY /= Double(avgCount)

            // Point in the current bucket forming the largest triangle with
            // `a` and the next bucket's average.
            let rangeStart = Int(Double(i) * bucketSize) + 1
            let rangeEnd = Swift.min(Int(Double(i + 1) * bucketSize) + 1, n)
            let ax = Double(points[a].x)
            let ay = Double(points[a].y)
            var maxArea = -1.0
            var chosen = rangeStart
            for j in rangeStart..<Swift.max(rangeEnd, rangeStart + 1) where j < n {
                let area =
                    abs(
                        (ax - avgX) * (Double(points[j].y) - ay)
                            - (ax - Double(points[j].x)) * (avgY - ay)
                    ) * 0.5
                if area > maxArea {
                    maxArea = area
                    chosen = j
                }
            }
            sampled.append(chosen)
            a = chosen
        }

        sampled.append(n - 1)
        return sampled
    }
}
