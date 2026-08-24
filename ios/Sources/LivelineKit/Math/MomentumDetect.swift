import Foundation

/// Auto-detects the line's ``Trend`` from recent samples, matching web
/// liveline's `detectMomentum`.
///
/// Only triggers during active movement: the threshold is a fraction of the
/// full-lookback range, but the velocity is measured over just the last few
/// points, so a line that drifted long ago but is now steady reads as `flat`.
public enum MomentumDetect {
    /// Detects the trend.
    /// - Parameters:
    ///   - points: The series (ascending in time).
    ///   - lookback: How many trailing points define the range (default 20).
    public static func detect(_ points: [LivelinePoint], lookback: Int = 20) -> Trend {
        guard points.count >= 5 else { return .flat }
        let start = Swift.max(0, points.count - lookback)

        var minV = Double.infinity
        var maxV = -Double.infinity
        for i in start..<points.count {
            let v = points[i].value
            if v < minV { minV = v }
            if v > maxV { maxV = v }
        }
        let range = maxV - minV
        if range == 0 { return .flat }

        let tailStart = Swift.max(start, points.count - 5)
        let first = points[tailStart].value
        let last = points[points.count - 1].value
        let delta = last - first
        let threshold = range * 0.12

        if delta > threshold { return .up }
        if delta < -threshold { return .down }
        return .flat
    }
}
