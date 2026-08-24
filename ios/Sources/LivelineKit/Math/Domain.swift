import Foundation

/// Holds the eased visible Y domain and advances it toward a target each frame,
/// matching web liveline's `updateRange` (steady-state path).
///
/// The target comes from ``AutoRange/compute(values:currentValue:referenceValue:exaggerate:)``.
/// Each frame the visible bounds lerp toward it with an adaptive speed, then
/// snap when they are within half a pixel — so the axis settles crisply instead
/// of creeping. There is deliberately **no hysteresis**; that is not how the
/// reference library behaves.
public struct Domain: Equatable, Sendable {
    /// Current visible lower bound.
    public private(set) var minVal: Double
    /// Current visible upper bound.
    public private(set) var maxVal: Double
    private var inited: Bool

    /// The current visible span (never zero).
    public var valRange: Double { (maxVal - minVal) == 0 ? 0.001 : (maxVal - minVal) }

    /// Creates an uninitialised domain. The first ``update(target:speed:dt:chartH:)``
    /// snaps directly to the target.
    public init() {
        self.minVal = 0
        self.maxVal = 1
        self.inited = false
    }

    /// Creates a domain seeded with explicit bounds (mainly for tests).
    public init(minVal: Double, maxVal: Double) {
        self.minVal = minVal
        self.maxVal = maxVal
        self.inited = true
    }

    /// Advances the domain by one frame.
    /// - Parameters:
    ///   - target: The target bounds from ``Range``.
    ///   - speed: Adaptive lerp speed (per 16.67 ms frame).
    ///   - dt: Elapsed time since the last update, in milliseconds.
    ///   - chartH: Chart height in points, for the sub-pixel snap threshold.
    public mutating func update(target: AutoRange.Bounds, speed: Double, dt: Double, chartH: Double) {
        if !inited {
            minVal = target.min
            maxVal = target.max
            inited = true
            return
        }
        let curRange = maxVal - minVal
        minVal = Clock.lerp(current: minVal, target: target.min, speed: speed, dt: dt)
        maxVal = Clock.lerp(current: maxVal, target: target.max, speed: speed, dt: dt)
        let pxThreshold = chartH != 0 ? 0.5 * curRange / chartH : 0.001
        let threshold = pxThreshold == 0 ? 0.001 : pxThreshold
        if abs(minVal - target.min) < threshold { minVal = target.min }
        if abs(maxVal - target.max) < threshold { maxVal = target.max }
    }

    /// Resets the domain so the next update snaps to its target.
    public mutating func reset() {
        inited = false
    }

    /// A ``Scale`` mapping this domain onto a pixel range. The range is usually
    /// inverted (`rangeMin` at the bottom) so larger values appear higher.
    public func scale(rangeMin: Double, rangeMax: Double) -> Scale {
        Scale(domainMin: minVal, domainMax: maxVal, rangeMin: rangeMin, rangeMax: rangeMax)
    }

    /// The adaptive lerp speed used for both the value and the range, matching
    /// liveline's `computeAdaptiveSpeed`: slower for big jumps, faster for small
    /// ticks. `base` is `lerpSpeed` (default 0.08); the boost is up to `+0.2`.
    public static func adaptiveSpeed(
        value: Double,
        displayValue: Double,
        displayMin: Double,
        displayMax: Double,
        base: Double,
        boost: Double = 0.2
    ) -> Double {
        let valGap = abs(value - displayValue)
        let prevRange = (displayMax - displayMin) == 0 ? 1 : (displayMax - displayMin)
        let gapRatio = Swift.min(valGap / prevRange, 1)
        return base + (1 - gapRatio) * boost
    }
}
