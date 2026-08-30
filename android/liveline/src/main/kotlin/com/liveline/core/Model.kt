package com.liveline.core

/**
 * A single sample in a line series: a value at a point in time.
 *
 * [time] is a monotonic timestamp in seconds (any epoch — only differences
 * matter). [value] is the measured quantity plotted on the y-axis.
 */
data class LivelinePoint(val time: Double, val value: Double)

/** A 2D point in double precision — the core's stand-in for CGPoint/PointF. */
data class Point(val x: Double, val y: Double)

/**
 * The resolved direction of the line, used to colour the badge and pick the
 * endpoint arrows. Mirrors web liveline's `Momentum` (`'up' | 'down' | 'flat'`)
 * — distinct from the [Momentum] *prop*, which also carries `off`/`auto`.
 */
enum class Trend(val value: String) { UP("up"), DOWN("down"), FLAT("flat") }

/**
 * Momentum tint behaviour. A single flat enum, unlike web liveline's
 * `true | 'up' | 'down' | 'flat'` union (an intentional divergence).
 */
enum class Momentum(val value: String) {
    OFF("off"), AUTO("auto"), UP("up"), DOWN("down"), FLAT("flat")
}

/** Chart type. `line` is the default; `candle` renders OHLC candlesticks. */
enum class LivelineMode(val value: String) { LINE("line"), CANDLE("candle") }

/** Base surface tone (background, grid and text); the accent is supplied via `color`. */
enum class LivelineTheme(val value: String) { LIGHT("light"), DARK("dark") }

/** Visual style of the endpoint value badge. */
enum class BadgeVariant(val value: String) {
    DEFAULT("default"), MINIMAL("minimal"), ACCENT("accent")
}

/** Visual style of the time-window button bar. */
enum class WindowStyle(val value: String) {
    DEFAULT("default"), ROUNDED("rounded"), TEXT("text")
}
