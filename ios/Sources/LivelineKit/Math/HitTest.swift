import Foundation

/// Binary search for the sample nearest a scrub position.
///
/// The render loop maps a touch x back to a time via ``Scale/invert(_:)`` and
/// asks ``nearest(times:x:)`` which sample the finger is over.
public enum HitTest {
    /// Returns the index of the sample whose time is closest to `x`.
    ///
    /// `times` must be sorted ascending. Ties resolve to the earlier index.
    /// Returns `nil` only for an empty array.
    public static func nearest(times: [Double], x: Double) -> Int? {
        guard !times.isEmpty else { return nil }
        if x <= times[0] { return 0 }
        let lastIndex = times.count - 1
        if x >= times[lastIndex] { return lastIndex }

        var lo = 0
        var hi = lastIndex
        while lo <= hi {
            let mid = (lo + hi) / 2
            let v = times[mid]
            if v == x { return mid }
            if v < x { lo = mid + 1 } else { hi = mid - 1 }
        }
        // `hi` is the last index below x, `lo` the first above.
        let before = hi
        let after = lo
        if before < 0 { return after }
        if after > lastIndex { return before }
        return (x - times[before] <= times[after] - x) ? before : after
    }
}
