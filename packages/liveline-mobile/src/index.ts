import * as React from 'react'
import { getHostComponent } from 'react-native-nitro-modules'

import LivelineConfig from '../nitrogen/generated/shared/json/LivelineConfig.json'
import type { LivelineMethods, LivelineProps } from './Liveline.nitro'

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
 * `surfaceColor` defaults to `''`, which the native side treats as "no
 * override" (theme default). Genuinely data-shaped props (`data`, `value`,
 * `candles`, `liveCandle`, `referenceLine`) are intentionally not defaulted.
 */
const defaults: Partial<LivelineProps> = {
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
  pulse: true,
  exaggerate: false,
  paused: false,
  loading: false,
  showValue: false,
  valueMomentumColor: false,
  window: 30,
  lineWidth: 2,
  lerpSpeed: 0.08,
  candleWidth: 1,
  emptyText: 'No data to display',
  surfaceColor: '',
  valuePrefix: '',
  valueSuffix: '',
  valueDecimals: 2,
}

type LivelineComponentProps = React.ComponentProps<typeof NativeLiveline>

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

function warnIfOverfed(props: LivelineComponentProps): void {
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

/**
 * The native Liveline chart, rendered by the Swift `LivelineView` via Nitro.
 * Props are declarative; the imperative `push()` is reached via `hybridRef`.
 *
 * A thin wrapper (not the raw host component) so that (a) omitting/removing any
 * prop falls back to its default instead of sending `null` — which Nitro
 * rejects on optional props — and (b) data-shaped props (`referenceLine`,
 * `data`, `candles`) coalesce to sentinels the native side treats as "unset",
 * so they can be toggled off without error.
 */
export function Liveline(props: LivelineComponentProps): React.ReactElement {
  warnIfOverfed(props)
  const merged = { ...defaults, ...defined(props) } as Record<string, unknown>
  if (merged.referenceLine == null) merged.referenceLine = { value: Number.NaN }
  if (merged.data == null) merged.data = []
  if (merged.candles == null) merged.candles = []
  return React.createElement(NativeLiveline, merged)
}

export type {
  LivelineProps,
  LivelineMethods,
  LivelinePoint,
  CandlePoint,
  LivelineReference,
  LivelineMode,
  LivelineTheme,
  LivelineMomentum,
  LivelineBadgeVariant,
} from './Liveline.nitro'
