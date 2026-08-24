import Foundation

/// Linear interpolation of a series at an arbitrary time, matching web
/// liveline's `interpolateAtTime`. Used to read the scrub value at the
/// crosshair. Points must be ascending in `time`.
public enum Interpolate {
    /// Returns the interpolated value at `time`, or `nil` if the series is empty.
    /// Times outside the series clamp to the nearest endpoint value.
    public static func atTime(_ points: [LivelinePoint], time: Double) -> Double? {
        guard !points.isEmpty else { return nil }
        if time <= points[0].time { return points[0].value }
        let lastIndex = points.count - 1
        if time >= points[lastIndex].time { return points[lastIndex].value }

        var lo = 0
        var hi = lastIndex
        while hi - lo > 1 {
            let mid = (lo + hi) >> 1
            if points[mid].time <= time { lo = mid } else { hi = mid }
        }

        let p1 = points[lo]
        let p2 = points[hi]
        let dt = p2.time - p1.time
        if dt == 0 { return p1.value }
        let t = (time - p1.time) / dt
        return p1.value + (p2.value - p1.value) * t
    }
}
