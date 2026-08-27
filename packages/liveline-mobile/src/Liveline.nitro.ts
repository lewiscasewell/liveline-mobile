import type { HybridView, HybridViewMethods, HybridViewProps } from 'react-native-nitro-modules'

/** A single sample in a line series. */
export interface LivelinePoint {
  /** Timestamp in unix seconds. */
  time: number
  /** The plotted value. */
  value: number
}

/** A single OHLC candle. */
export interface CandlePoint {
  /** Timestamp of the candle's open, in unix seconds. */
  time: number
  /** Price at the start of the interval. */
  open: number
  /** Highest price during the interval. */
  high: number
  /** Lowest price during the interval. */
  low: number
  /** Price at the end of the interval. */
  close: number
}

/** A horizontal reference line at a fixed value. */
export interface LivelineReference {
  /** The value at which the line is drawn (kept in view by the autoscale). */
  value: number
  /** Optional centred label; the line breaks around the text. */
  label?: string
}

/** Chart inset overrides (points); any omitted side keeps its default. */
export interface LivelinePadding {
  top?: number
  right?: number
  bottom?: number
  left?: number
}

/** One equal-peer line in multi-series mode (see the `series` prop). */
export interface LivelineSeries {
  /** Stable id, used to route live `push(point, id)` updates to this series. */
  id: string
  /** Line colour (any CSS hex). */
  color: string
  /** Optional label — shown on the legend chip and the endpoint label. */
  label?: string
  /** The series' points (backfill; stream live updates via `push(point, id)`). */
  data: LivelinePoint[]
}

/** One order-book level: a resting `size` at a `price`. */
export interface LivelineOrderbookLevel {
  /** The level's price. */
  price: number
  /** The resting size at that price (drives the label + its brightness). */
  size: number
}

/** A snapshot of bid/ask depth. Its resting sizes stream up behind the line. */
export interface LivelineOrderbook {
  /** Bid levels (up-colour). */
  bids: LivelineOrderbookLevel[]
  /** Ask levels (down-colour). */
  asks: LivelineOrderbookLevel[]
}

/** Chart type. */
export type LivelineMode = 'line' | 'candle'
/** Theme tone — sets the colour of the line, grid, labels, text and crosshair. */
export type LivelineTheme = 'light' | 'dark'
/**
 * Momentum behaviour. A single flat enum, unlike web's `true | 'up' | 'down' |
 * 'flat'` union — this mobile divergence is recorded in `spec/API.md`.
 * - `off`: no momentum tint or arrows.
 * - `auto`: direction detected from recent movement.
 * - `up` / `down` / `flat`: forced direction.
 */
export type LivelineMomentum = 'off' | 'auto' | 'up' | 'down' | 'flat'
/** Badge visual style: `default` (accent-filled) or `minimal` (neutral pill). */
export type LivelineBadgeVariant = 'default' | 'minimal' | 'accent'

/** Visual style of the built-in time-window bar. */
export type LivelineWindowStyle = 'default' | 'rounded' | 'text'

/** One button in the built-in time-window bar. */
export interface WindowOption {
  /** Button text, e.g. `'1D'`. */
  label: string
  /** The visible span this button selects, in seconds. */
  secs: number
}

/**
 * Props for the {@link Liveline} view. Names mirror the Swift/SwiftUI API and,
 * where they exist, web liveline. Every prop is optional and has a sensible
 * default; the JS wrapper supplies defaults so omitting a prop never errors.
 */
export interface LivelineProps extends HybridViewProps {
  /**
   * Backfill history — the initial series drawn when the chart mounts. This is
   * **not** the live path; for streaming updates call `push()` via `hybridRef`
   * (a growing `data` array re-marshalled every tick is exactly what this
   * native view exists to avoid).
   *
   * Give it roughly the visible window's resolution — a chart only draws ~one
   * point per horizontal pixel, so a few hundred evenly-spaced points is plenty
   * for any timeframe. Pre-decimate wide ranges (e.g. one point per day for a
   * multi-year view) rather than shipping every raw tick: past ~8192 points the
   * native buffer drops the oldest, and the JS wrapper warns in dev above a few
   * thousand.
   */
  data?: LivelinePoint[]
  /**
   * Multi-series mode: several **equal-peer** lines on one chart. A non-empty
   * array replaces `data`/`value` (there's no single-series badge/value/momentum
   * in this mode). Each series draws its own colour, endpoint dot, dashed
   * baseline and label; the Y-axis auto-ranges over the visible series; a legend
   * of toggle chips renders above the chart. Line mode only. Stream live updates
   * with `push(point, id)`.
   */
  series?: LivelineSeries[]
  /** Compact legend: colour dots only, no labels. Default `false`. */
  seriesToggleCompact?: boolean
  /** Called when a legend chip toggles a series' visibility. */
  onSeriesToggle?: (id: string, visible: boolean) => void
  /**
   * A single live value; each distinct value is appended as a new sample.
   *
   * ⚠️ Setting this prop **re-renders React on every change.** Fine for
   * low-frequency, React-driven updates — but at high rates it saturates the JS
   * thread and *drops* ticks. Measured on-device at a 60Hz feed: `value` manages
   * only ~40 renders/s (leaf) or ~22/s (in a real screen) and can't keep up,
   * versus `push()` at **0 renders/s** (the chart stays 60fps either way — it's
   * the JS thread that suffers).
   *
   * **For anything real-time, prefer the imperative `push()` via `useLiveline()`**
   * — it goes straight to native, bypassing React entirely.
   */
  value?: number

  /** Chart type. Default `'line'`. */
  mode?: LivelineMode
  /** OHLC candles (required when `mode` is `'candle'`). */
  candles?: CandlePoint[]
  /** Seconds per candle (required when `mode` is `'candle'`). */
  candleWidth?: number
  /** The current, still-forming candle with real-time OHLC. */
  liveCandle?: CandlePoint

  /** Accent colour (any CSS hex). Derives the line, fill and badge. Default `'#3b82f6'`. */
  color?: string
  /**
   * Tone of the line, grid, labels, text and crosshair (`'light'` | `'dark'`).
   * Default `'dark'`. It does not paint a background — set it to match whatever
   * background sits behind the chart.
   */
  theme?: LivelineTheme
  /**
   * Opaque background fill. Omit (or `''`) and the chart is transparent — the
   * view behind it shows through, matching web liveline. Pass a hex to make the
   * chart a self-contained card instead; `theme` still sets the tone.
   */
  surfaceColor?: string
  /** Line stroke width in points. Default `2`. */
  lineWidth?: number

  /** Visible time span in seconds. Default `30`. */
  window?: number

  /**
   * Render the built-in interval bar with these buttons above the chart. The
   * native view draws it (a segmented control) and reports taps via
   * `onWindowChange`; the active button is the one whose `secs` matches `window`.
   */
  windows?: WindowOption[]
  /** Visual style of the window bar. Default `'default'`. */
  windowStyle?: LivelineWindowStyle
  /** Called with the chosen span (seconds) when a window button is tapped. */
  onWindowChange?: (secs: number) => void
  /**
   * When set, the window bar shows an optional line/candle mode toggle at its
   * end; this fires with the chosen mode when tapped. Drive `mode` from it.
   */
  onModeChange?: (mode: LivelineMode) => void

  /** Draw the value grid lines + right-edge value labels. Default `true`. */
  grid?: boolean
  /** Draw the endpoint value badge (the pill on the right). Default `true`. */
  badge?: boolean
  /** Draw the badge's pointed tail toward the live dot. Default `true`. */
  badgeTail?: boolean
  /**
   * Badge visual style. Default `'default'` (momentum green/red). `'minimal'`
   * is a neutral pill; `'accent'` fills with the line colour (arrows still show).
   */
  badgeVariant?: LivelineBadgeVariant
  /** Momentum tint (badge) + directional arrows on the live dot. Default `'auto'`. */
  momentum?: LivelineMomentum
  /** Fill the area under the line with the accent gradient. Default `true`. */
  fill?: boolean
  /** Enable the touch crosshair (press-and-hold to scrub). Default `true`. */
  scrub?: boolean
  /** Vertical offset (points) of the crosshair tooltip text. Default `14`. */
  tooltipY?: number
  /** Stroke an outline behind the crosshair tooltip text. Default `true`. */
  tooltipOutline?: boolean
  /** Override the chart insets (points). Any omitted side keeps its default. */
  padding?: LivelinePadding
  /** Pulsing ring on the live dot. Default `true`. */
  pulse?: boolean
  /** Tighten the Y-axis range so small moves fill the chart height. Default `false`. */
  exaggerate?: boolean
  /** Freeze scrolling while data keeps arriving; catches up on resume. Default `false`. */
  paused?: boolean
  /** Show the breathing loading animation; morphs into the chart when data arrives. Default `false`. */
  loading?: boolean
  /** Message shown in the empty state. Default `'No data to display'`. */
  emptyText?: string
  /** Draw the live value as a large text overlay over the chart. Default `false`. */
  showValue?: boolean
  /** Tint the `showValue` overlay by momentum (green up / red down). Default `false`. */
  valueMomentumColor?: boolean
  /**
   * Haptic feedback: a light tap as the crosshair crosses each step while
   * scrubbing, and a stronger hit on every degen burst. Default `true`.
   */
  haptics?: boolean
  /**
   * Degen mode: on a strong upward move the chart shakes and sparks burst from
   * the live dot (with a haptic hit when `haptics` is on). Default `false`.
   */
  degen?: boolean
  /** Base easing speed per 60fps frame (`0…1`); lower is smoother/slower. Default `0.08`. */
  lerpSpeed?: number
  /** A horizontal reference line at a fixed value. Omit to remove it. */
  referenceLine?: LivelineReference

  /**
   * Order-book depth (`{ bids, asks }`). The resting sizes stream up behind the
   * price line — bids in the up-colour, asks in the down-colour, bigger orders
   * brighter — with a drift speed that reacts to price momentum and book churn.
   * A convenience for React-driven updates; prefer `pushOrderbook()` for a
   * high-frequency depth feed. Pair with `value`/`push()` for the price line.
   */
  orderbook?: LivelineOrderbook

  /** Prepended to every formatted value (e.g. `'$'`). Ignored when `currency` is set. */
  valuePrefix?: string
  /** Appended to every formatted value (e.g. `' bpm'`). Ignored when `currency` is set. */
  valueSuffix?: string
  /** Decimal places for formatted values. Default `2` (or the currency's default). */
  valueDecimals?: number
  /**
   * ISO 4217 currency code (e.g. `'USD'`, `'EUR'`, `'JPY'`). Formats values as
   * localized currency — symbol, its placement and the default decimals all
   * follow `locale`. Overrides `valuePrefix`/`valueSuffix`.
   */
  currency?: string
  /**
   * BCP-47 locale (e.g. `'de-DE'`) for number *and* time formatting — decimal /
   * grouping separators, month names, field order, 12/24-hour. Defaults to the
   * device locale.
   */
  locale?: string
  /** Thousands separators. Default: off for plain values, on for currency. */
  useGrouping?: boolean
  /**
   * Font family for all chart text. The family must be registered by the host
   * app (bundled + linked, e.g. via `expo-font`); an unregistered name falls
   * back to the system font. Numeric labels always keep monospaced digits.
   * Default: the system monospaced font.
   */
  fontFamily?: string
}

/** Imperative methods, reached via `hybridRef`. */
export interface LivelineMethods extends HybridViewMethods {
  /**
   * Add one live sample. **The recommended way to stream a live feed** — a direct
   * native call with **no React re-render** (unlike the `value` prop, which
   * re-renders on every change; see its note). Call once per data tick, never per
   * animation frame. It auto-adapts to the current window: on a wide window a fast
   * feed slides the current point in place; on a live/short window it keeps every
   * tick.
   *
   * In multi-series mode, pass `seriesId` to route the tick to that series (see
   * `series`); omit it for the single-series line.
   */
  push(point: LivelinePoint, seriesId?: string): void

  /**
   * Replace the current order book. A direct native call with no React
   * re-render — the efficient path for a high-frequency depth feed (mirrors how
   * `push()` streams the price line). Equivalent to setting the `orderbook` prop.
   */
  pushOrderbook(orderbook: LivelineOrderbook): void
}

export type Liveline = HybridView<LivelineProps, LivelineMethods>
