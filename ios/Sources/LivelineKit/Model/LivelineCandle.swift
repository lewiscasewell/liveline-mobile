import Foundation

/// A single OHLC candle. Reserved for candle mode (Phase 3+); the value type is
/// defined now so the data vocabulary is stable across platforms.
public struct LivelineCandle: Equatable, Hashable, Sendable {
    /// Timestamp of the candle's open, in seconds.
    public var time: Double
    /// Price at the start of the interval.
    public var open: Double
    /// Highest price during the interval.
    public var high: Double
    /// Lowest price during the interval.
    public var low: Double
    /// Price at the end of the interval.
    public var close: Double

    /// Creates a candle.
    public init(time: Double, open: Double, high: Double, low: Double, close: Double) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }

    /// `true` when the close is at or above the open.
    public var isUp: Bool { close >= open }
}
