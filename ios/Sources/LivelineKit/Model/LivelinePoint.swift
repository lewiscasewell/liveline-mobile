import CoreGraphics
import Foundation

/// A single sample in a line series: a value at a point in time.
///
/// `time` is a monotonic timestamp in seconds (any epoch — only differences
/// matter). `value` is the measured quantity plotted on the y-axis.
public struct LivelinePoint: Equatable, Hashable, Sendable {
    /// Timestamp in seconds. Only relative differences are significant.
    public var time: Double
    /// The plotted quantity.
    public var value: Double

    /// Creates a point.
    /// - Parameters:
    ///   - time: Timestamp in seconds.
    ///   - value: The plotted quantity.
    public init(time: Double, value: Double) {
        self.time = time
        self.value = value
    }
}
