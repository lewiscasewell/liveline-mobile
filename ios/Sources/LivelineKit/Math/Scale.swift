import Foundation

/// A linear mapping from a `domain` interval onto a `range` interval, with its
/// inverse. Used for both axes: time → x-pixels, and value → y-pixels (where
/// the range is usually inverted, `rangeMin` at the bottom of the view).
///
/// A degenerate domain (`domainMin == domainMax`) maps everything to `rangeMin`.
public struct Scale: Equatable, Sendable {
    /// Lower bound of the input interval.
    public var domainMin: Double
    /// Upper bound of the input interval.
    public var domainMax: Double
    /// Output value corresponding to `domainMin`.
    public var rangeMin: Double
    /// Output value corresponding to `domainMax`.
    public var rangeMax: Double

    /// Creates a linear scale.
    public init(domainMin: Double, domainMax: Double, rangeMin: Double, rangeMax: Double) {
        self.domainMin = domainMin
        self.domainMax = domainMax
        self.rangeMin = rangeMin
        self.rangeMax = rangeMax
    }

    /// Projects a domain value into the range.
    public func scale(_ x: Double) -> Double {
        let d = domainMax - domainMin
        if d == 0 { return rangeMin }
        let t = (x - domainMin) / d
        return rangeMin + t * (rangeMax - rangeMin)
    }

    /// Maps a range value back into the domain.
    public func invert(_ y: Double) -> Double {
        let r = rangeMax - rangeMin
        if r == 0 { return domainMin }
        let t = (y - rangeMin) / r
        return domainMin + t * (domainMax - domainMin)
    }
}
