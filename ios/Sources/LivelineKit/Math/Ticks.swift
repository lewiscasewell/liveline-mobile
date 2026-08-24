import Foundation

/// Grid interval selection for the value axis, matching web liveline's
/// `pickInterval` (a TradingView-style cycling-divisor search) with hysteresis:
/// once an interval is chosen it is kept until its on-screen spacing falls
/// outside `[0.5×, 4×]` of the minimum gap, which stops the grid from
/// flickering as the domain eases.
///
/// The caller draws a *coarse* interval (always visible) and a *fine* interval
/// at `coarse / 2` (faded in when there is room). The per-label alpha animation
/// lives in the view; this type only picks numbers.
public enum Ticks {
    /// Picks the coarse interval.
    /// - Parameters:
    ///   - valRange: The visible value span.
    ///   - pxPerUnit: Pixels per value unit (`chartH / valRange`).
    ///   - minGap: Minimum pixel gap between coarse labels (liveline uses 36).
    ///   - prev: The previously chosen interval, for hysteresis (0 if none).
    public static func pickInterval(
        valRange: Double,
        pxPerUnit: Double,
        minGap: Double,
        prev: Double
    ) -> Double {
        if prev > 0 {
            let px = prev * pxPerUnit
            if px >= minGap * 0.5, px <= minGap * 4 { return prev }
        }

        let divisorSets: [[Double]] = [[2, 2.5, 2], [2, 2, 2.5], [2.5, 2, 2]]
        var best = Double.infinity
        for divs in divisorSets {
            guard valRange > 0 else { continue }
            var span = pow(10, (log10(valRange)).rounded(.up))
            var i = 0
            while span / divs[i % 3] * pxPerUnit >= minGap {
                span /= divs[i % 3]
                i += 1
            }
            if span < best { best = span }
        }
        return best == Double.infinity ? valRange / 5 : best
    }

    /// Float-safe check that `val` is an integer multiple of `interval`.
    public static func divisible(_ val: Double, by interval: Double) -> Bool {
        guard interval != 0 else { return false }
        let ratio = val / interval
        return abs(ratio - ratio.rounded()) < 0.01
    }
}
