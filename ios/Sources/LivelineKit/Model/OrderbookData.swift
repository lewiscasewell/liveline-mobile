import Foundation

/// One level of an order book: a resting `size` at a `price`.
public struct OrderbookLevel: Equatable, Sendable {
    public let price: Double
    public let size: Double
    public init(price: Double, size: Double) {
        self.price = price
        self.size = size
    }
}

/// A snapshot of bid/ask depth, mirroring web liveline's `orderbook` prop
/// (`{ bids, asks }`, each `[price, size]`). The chart floats the resting sizes
/// upward behind the price line — bids in the up-colour, asks in the down-colour
/// — with a drift speed that reacts to price momentum.
public struct OrderbookData: Equatable, Sendable {
    public var bids: [OrderbookLevel]
    public var asks: [OrderbookLevel]
    public init(bids: [OrderbookLevel], asks: [OrderbookLevel]) {
        self.bids = bids
        self.asks = asks
    }

    /// Convenience for `[price, size]` tuples (matches the web/JS shape).
    public init(bidTuples: [[Double]], askTuples: [[Double]]) {
        self.bids = bidTuples.compactMap { $0.count >= 2 ? OrderbookLevel(price: $0[0], size: $0[1]) : nil }
        self.asks = askTuples.compactMap { $0.count >= 2 ? OrderbookLevel(price: $0[0], size: $0[1]) : nil }
    }
}
