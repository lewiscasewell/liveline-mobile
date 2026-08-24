import Foundation

/// Computes the target visible Y range from the data, matching web liveline's
/// `computeRange`. The range spans the visible values, the current live value,
/// and an optional reference line, then adds a margin (or opens a minimum
/// window when the data is nearly flat).
///
/// `exaggerate` tightens the margin so small movements fill the chart height.
///
/// Named `AutoRange` rather than `Range` to avoid shadowing Swift's `Range`.
public enum AutoRange {
    /// The computed target range.
    public struct Bounds: Equatable, Sendable {
        /// Lower bound.
        public var min: Double
        /// Upper bound.
        public var max: Double

        /// Creates bounds.
        public init(min: Double, max: Double) {
            self.min = min
            self.max = max
        }
    }

    /// Computes the target range.
    /// - Parameters:
    ///   - values: Visible sample values.
    ///   - currentValue: The current live value (always included).
    ///   - referenceValue: Optional reference-line value to keep in view.
    ///   - exaggerate: When `true`, use a tight margin.
    public static func compute(
        values: [Double],
        currentValue: Double,
        referenceValue: Double? = nil,
        exaggerate: Bool = false
    ) -> Bounds {
        var targetMin = Double.infinity
        var targetMax = -Double.infinity

        for v in values {
            if v < targetMin { targetMin = v }
            if v > targetMax { targetMax = v }
        }
        if currentValue < targetMin { targetMin = currentValue }
        if currentValue > targetMax { targetMax = currentValue }
        if let ref = referenceValue {
            if ref < targetMin { targetMin = ref }
            if ref > targetMax { targetMax = ref }
        }

        // Guard against no data at all.
        if !targetMin.isFinite || !targetMax.isFinite {
            targetMin = currentValue - 0.5
            targetMax = currentValue + 0.5
        }

        let rawRange = targetMax - targetMin
        let marginFactor = exaggerate ? 0.01 : 0.12
        let scaled = rawRange * (exaggerate ? 0.02 : 0.1)
        let minRange = scaled != 0 ? scaled : (exaggerate ? 0.04 : 0.4)

        if rawRange < minRange {
            let mid = (targetMin + targetMax) / 2
            targetMin = mid - minRange / 2
            targetMax = mid + minRange / 2
        } else {
            let margin = rawRange * marginFactor
            targetMin -= margin
            targetMax += margin
        }

        return Bounds(min: targetMin, max: targetMax)
    }

    /// Computes the target range for candle mode from OHLC lows/highs, matching
    /// web liveline's `computeCandleRange`.
    public static func computeCandles(_ candles: [LivelineCandle]) -> Bounds {
        var minV = Double.infinity
        var maxV = -Double.infinity
        for c in candles {
            if c.low < minV { minV = c.low }
            if c.high > maxV { maxV = c.high }
        }
        if !minV.isFinite || !maxV.isFinite { return Bounds(min: 99, max: 101) }
        let range = maxV - minV
        let margin = range * 0.12
        let scaled = range * 0.1
        let minRange = scaled != 0 ? scaled : 0.4
        if range < minRange {
            let mid = (minV + maxV) / 2
            return Bounds(min: mid - minRange / 2, max: mid + minRange / 2)
        }
        return Bounds(min: minV - margin, max: maxV + margin)
    }
}
