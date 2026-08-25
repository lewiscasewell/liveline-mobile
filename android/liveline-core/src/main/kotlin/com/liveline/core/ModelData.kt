package com.liveline.core

/**
 * A single OHLC candle. [isUp] is `true` when the close is at or above the open.
 */
data class LivelineCandle(
    val time: Double,
    val open: Double,
    val high: Double,
    val low: Double,
    val close: Double,
) {
    val isUp: Boolean get() = close >= open
}

/**
 * A horizontal reference line at a fixed value, with an optional label. The
 * value is always kept in view by the autoscale.
 */
data class ReferenceLine(val value: Double, val label: String? = null)

/**
 * A named time window, e.g. `Window("1m", 60.0)`. Windows describe how much
 * history is visible; the render loop scrolls to keep [secs] seconds on screen.
 */
data class Window(val label: String, val secs: Double) {
    /** Stable identity derived from the label. */
    val id: String get() = label
}

/** One order-book level: a resting [size] at a [price]. */
data class OrderbookLevel(val price: Double, val size: Double)

/**
 * A snapshot of bid/ask depth. Its resting sizes stream up behind the price
 * line — bids in the up-colour, asks in the down-colour.
 */
data class OrderbookData(val bids: List<OrderbookLevel>, val asks: List<OrderbookLevel>)
