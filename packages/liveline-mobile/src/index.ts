import * as React from 'react'
import { callback, getHostComponent } from 'react-native-nitro-modules'

import LivelineConfig from '../nitrogen/generated/shared/json/LivelineConfig.json'
import type { LivelineCurrency } from './currencies'
import type {
  LivelineMethods,
  LivelineMode,
  LivelineOrderbook,
  LivelinePoint,
  LivelineProps,
} from './Liveline.nitro'

/**
 * Order-book depth, matching web liveline: `bids`/`asks` are arrays of
 * `[price, size]` tuples. The resting sizes stream up behind the price line.
 */
export interface LivelineOrderbookData {
  bids: [number, number][]
  asks: [number, number][]
}

/** Convert the public `[price, size]` tuples to the native `{ price, size }` shape. */
function toNativeOrderbook(o: LivelineOrderbookData | undefined): LivelineOrderbook {
  const conv = (arr: [number, number][] | undefined) =>
    (arr ?? []).map(([price, size]) => ({ price, size }))
  return { bids: conv(o?.bids), asks: conv(o?.asks) }
}

const NativeLiveline = getHostComponent<LivelineProps, LivelineMethods>(
  'Liveline',
  () => LivelineConfig
)

/**
 * Default prop values, matching the native `LivelineView` defaults.
 *
 * These exist because (1) Nitro's view-prop bridge throws on an explicit `null`
 * for optional props, and (2) React 19 dropped `defaultProps` for function
 * components. Spreading these first means a prop the caller omits (or removes)
 * always arrives as its default value, never `null` — so nothing throws.
 *
 * `surfaceColor` defaults to `''`, which the native side treats as "no fill" —
 * the chart is transparent and the view behind it shows through (web parity).
 * Genuinely data-shaped props (`data`, `value`, `candles`, `liveCandle`,
 * `referenceLine`) are intentionally not defaulted.
 */
// Required for every prop the native side reads as a scalar/enum: Fabric sends
// `null` for any omitted attribute, and Nitro's view-prop bridge rejects null
// for these. Typing it as `Required<Omit<…, dataProps>>` makes a missing default
// a COMPILE error instead of a runtime crash. The excluded props are data-shaped
// (coalesced to sentinels below) or callbacks (wrapped separately).
type DefaultableProps = Omit<
  LivelineProps,
  'data' | 'value' | 'series' | 'candles' | 'liveCandle' | 'referenceLine' | 'orderbook' | 'windows' | 'onWindowChange' | 'onModeChange' | 'onSeriesToggle' | 'padding'
>
const defaults: Required<DefaultableProps> = {
  color: '#3b82f6',
  theme: 'dark',
  mode: 'line',
  grid: true,
  badge: true,
  badgeTail: true,
  badgeVariant: 'default',
  momentum: 'auto',
  fill: true,
  scrub: true,
  tooltipY: 14,
  tooltipOutline: true,
  seriesToggleCompact: false,
  pulse: true,
  exaggerate: false,
  paused: false,
  loading: false,
  showValue: false,
  valueMomentumColor: false,
  haptics: false,
  degen: false,
  window: 30,
  windowStyle: 'default',
  lineWidth: 2,
  lerpSpeed: 0.08,
  candleWidth: 1,
  emptyText: 'No data to display',
  surfaceColor: '',
  valuePrefix: '',
  valueSuffix: '',
  valueDecimals: 2,
  currency: '',
  locale: '',
  useGrouping: true,
  fontFamily: '',
}

// The native props now include the window bar (`windows`/`windowStyle`/
// `onWindowChange`) — the bar is drawn natively, so the wrapper just passes them
// through.
type LivelineComponentProps = React.ComponentProps<typeof NativeLiveline>

/**
 * Props of the `<Liveline>` wrapper. Same as the native props, except
 * `onWindowChange` is a plain function — the wrapper wraps it in Nitro's
 * `callback()` for you (like `hybridRef`), so callers never touch that plumbing.
 */
export type LivelineComponentPropsPublic = Omit<
  LivelineComponentProps,
  'onWindowChange' | 'onModeChange' | 'onSeriesToggle' | 'currency' | 'orderbook'
> & {
  onWindowChange?: (secs: number) => void
  onModeChange?: (mode: LivelineMode) => void
  onSeriesToggle?: (id: string, visible: boolean) => void
  // Native side takes any string; narrow the public API to valid ISO 4217 codes.
  currency?: LivelineCurrency
  // Public API takes web-style `[price, size]` tuples; converted for native.
  orderbook?: LivelineOrderbookData
}

declare const __DEV__: boolean | undefined

/**
 * Above this many points the chart is being over-fed: it only draws ~one point
 * per horizontal pixel, so extra points are decimated away, and points beyond
 * the native ring buffer (~8192) are silently dropped. Pre-decimate your data
 * to roughly the view's resolution (a few hundred points) instead. Crossing
 * this emits a one-time `console.warn` in dev; it has no effect in production.
 */
const MAX_RECOMMENDED_POINTS = 4000

let warnedOverfeed = false

function warnIfOverfed(props: { data?: unknown; candles?: unknown }): void {
  if (typeof __DEV__ === 'undefined' || !__DEV__) return
  const dataLen = Array.isArray(props.data) ? props.data.length : 0
  const candleLen = Array.isArray(props.candles) ? props.candles.length : 0
  const len = Math.max(dataLen, candleLen)
  if (len > MAX_RECOMMENDED_POINTS && !warnedOverfeed) {
    warnedOverfeed = true
    console.warn(
      `[liveline] Received ${len} points, more than the recommended ` +
        `${MAX_RECOMMENDED_POINTS}. A chart only draws ~1 point per pixel and the ` +
        `native buffer holds ~8192 (older points are dropped past that). Pre-decimate ` +
        `to roughly the visible window's resolution — a few hundred points — for the ` +
        `best performance and to avoid losing history.`
    )
  } else if (len <= MAX_RECOMMENDED_POINTS) {
    warnedOverfeed = false // reset so a later spike warns again
  }
}

/** Drops keys whose value is `null`/`undefined`, so they can't override a default. */
function defined<T extends object>(obj: T): Partial<T> {
  const out: Partial<T> = {}
  for (const key in obj) {
    if (obj[key] != null) out[key] = obj[key]
  }
  return out
}

// ─── Imperative access: useLiveline() + LivelineProvider ─────────────────────

/** The imperative handle exposed by the native chart (push). */
export type LivelineHandle = LivelineMethods

const LivelineRefContext =
  React.createContext<React.MutableRefObject<LivelineHandle | null> | null>(null)

/**
 * Shares one chart handle across a subtree so `useLiveline().push()` can be
 * called from a component OTHER than the one rendering `<Liveline>`. A
 * `<Liveline>` inside a provider auto-registers its handle — you don't wire a
 * `hybridRef` at all.
 */
export function LivelineProvider(props: { children?: React.ReactNode }): React.ReactElement {
  const ref = React.useRef<LivelineHandle | null>(null)
  return React.createElement(LivelineRefContext.Provider, { value: ref }, props.children)
}

/**
 * Owns the ref + imperative calls for a chart, so callers never touch
 * `hybridRef`/`callback` plumbing. Returns `push` (a safe no-op until the chart
 * mounts) and a stable `hybridRef` (with an `attachHybridRef()` alias) to wire
 * it up:
 *
 * ```tsx
 * const { attachHybridRef, push } = useLiveline()
 * push({ time, value })
 * <Liveline {...rest} hybridRef={attachHybridRef()} />
 * ```
 *
 * Inside a `<LivelineProvider>` it targets the shared handle, so `push()` works
 * anywhere in the subtree and `<Liveline>` needs no `hybridRef`.
 */
export function useLiveline() {
  const ctxRef = React.useContext(LivelineRefContext)
  const localRef = React.useRef<LivelineHandle | null>(null)
  const ref = ctxRef ?? localRef
  const hybridRef = React.useMemo(
    () => callback((r: LivelineHandle) => { ref.current = r }),
    [ref]
  )
  const push = React.useCallback(
    (point: LivelinePoint, seriesId?: string) => ref.current?.push(point, seriesId),
    [ref]
  )
  const pushOrderbook = React.useCallback(
    (orderbook: LivelineOrderbookData) => ref.current?.pushOrderbook(toNativeOrderbook(orderbook)),
    [ref]
  )
  const attachHybridRef = React.useCallback(() => hybridRef, [hybridRef])
  return { push, pushOrderbook, hybridRef, attachHybridRef }
}

/**
 * The native Liveline chart, rendered by the Swift `LivelineView` via Nitro,
 * plus an optional built-in interval bar. Props are declarative; the imperative
 * `push()` is reached via `hybridRef` (or, more simply, `useLiveline()`).
 *
 * A thin wrapper (not the raw host component) so that (a) omitting/removing any
 * prop falls back to its default instead of sending `null` — which Nitro rejects
 * on optional props; and (b) data-shaped props (`referenceLine`, `data`,
 * `candles`) coalesce to sentinels the native side treats as "unset". The
 * interval bar (`windows`/`windowStyle`/`onWindowChange`) is drawn natively, so
 * those props just pass straight through.
 */
export function Liveline(props: LivelineComponentPropsPublic): React.ReactElement {
  const ctxRef = React.useContext(LivelineRefContext)
  const { onWindowChange, onModeChange, onSeriesToggle, ...rest } = props
  // Auto-register with the nearest LivelineProvider when the caller didn't pass
  // a hybridRef, so `useLiveline().push()` works with zero manual wiring.
  const autoHybridRef = React.useMemo(
    () => (ctxRef ? callback((r: LivelineHandle) => { ctxRef.current = r }) : undefined),
    [ctxRef]
  )
  warnIfOverfed(rest)
  const merged = { ...defaults, ...defined(rest) } as Record<string, unknown>
  if (merged.referenceLine == null) merged.referenceLine = { value: Number.NaN }
  if (merged.data == null) merged.data = []
  if (merged.series == null) merged.series = []
  if (merged.candles == null) merged.candles = []
  if (merged.windows == null) merged.windows = []
  if (merged.padding == null) merged.padding = {}
  // Convert the web-style `[price, size]` tuples to the native `{ price, size }`
  // shape (an empty book is the "unset" sentinel, so it's never null).
  merged.orderbook = toNativeOrderbook(rest.orderbook as LivelineOrderbookData | undefined)
  if (merged.hybridRef == null && autoHybridRef) merged.hybridRef = autoHybridRef
  // Wrap the callbacks for Nitro (like hybridRef).
  if (onWindowChange) merged.onWindowChange = callback(onWindowChange)
  if (onModeChange) merged.onModeChange = callback(onModeChange)
  if (onSeriesToggle) merged.onSeriesToggle = callback(onSeriesToggle)
  return React.createElement(NativeLiveline, merged)
}

export type {
  WindowOption,
  LivelineWindowStyle,
  LivelinePadding,
  LivelineProps,
  LivelineMethods,
  LivelinePoint,
  CandlePoint,
  LivelineReference,
  LivelineSeries,
  LivelineOrderbook,
  LivelineOrderbookLevel,
  LivelineMode,
  LivelineTheme,
  LivelineMomentum,
  LivelineBadgeVariant,
} from './Liveline.nitro'
export type { LivelineCurrency } from './currencies'
