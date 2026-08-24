import Foundation

/// Chart type. `line` is the default; `candle` renders OHLC candlesticks.
public enum LivelineMode: String, Equatable, Hashable, Sendable, CaseIterable {
    case line
    case candle
}
