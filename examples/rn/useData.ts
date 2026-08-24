import { useEffect, useState } from 'react'
import type { LivelinePoint } from 'react-native-liveline-mobile'

/** The raw shape a "server" returns — deliberately different from LivelinePoint. */
export type RawTick = { ts: number; price: number }

/**
 * A selectable timeframe — just a visible span. Every timeframe reads the SAME
 * underlying history; switching only changes the window, so the native chart
 * smoothly zooms between them instead of swapping datasets.
 */
export type Timeframe = {
  label: string
  seconds: number
  /** Live timeframes keep streaming new ticks after the history loads. */
  live?: boolean
}

const DAY = 86400

export const TIMEFRAMES: Timeframe[] = [
  { label: '4Y', seconds: 4 * 365 * DAY },
  { label: '1Y', seconds: 365 * DAY },
  { label: '1M', seconds: 30 * DAY },
  { label: '1W', seconds: 7 * DAY },
  { label: '1D', seconds: DAY },
  { label: '4H', seconds: 4 * 3600 },
  { label: '1H', seconds: 3600 },
  { label: '30M', seconds: 1800 },
  { label: 'Live', seconds: 60, live: true },
]

/**
 * How densely to sample each slice of history, newest → oldest. You keep every
 * tick for the last half hour, but only ~fortnightly points four years back —
 * so a 4Y view is a clean handful of points, a 30M view is fine-grained, and
 * both are slices of one continuous series. ~950 points total.
 */
const SEGMENTS: { backTo: number; dt: number }[] = [
  { backTo: 1800, dt: 20 }, // last 30m  @ 20s  (smooth 30M; live push adds finer)
  { backTo: 4 * 3600, dt: 120 }, // 4h   @ 2m
  { backTo: DAY, dt: 900 }, // 1d        @ 15m
  { backTo: 7 * DAY, dt: 2 * 3600 }, // 1w  @ 2h
  { backTo: 30 * DAY, dt: 12 * 3600 }, // 1mo @ 12h
  { backTo: 365 * DAY, dt: 2 * DAY }, // 1y  @ 2d
  { backTo: 4 * 365 * DAY, dt: 10 * DAY }, // 4y @ 10d
]

export const MEAN = 100
/** Volatility per √second — self-similar at every zoom. The live feed reuses
 *  this so streamed ticks share the history's texture (no spike on switch). */
export const PRICE_VOL = 0.02
const REVERT = 4e-7 // mean-reversion per second — bounds the multi-year drift

/**
 * One continuous mean-reverting walk, sampled at the resolutions above. Built
 * backwards from `now` so it ends exactly on the anchor price (the live feed
 * continues from there). Volatility scales with √dt, so the curve looks equally
 * natural whether you're viewing 30 minutes or 4 years, and reversion keeps the
 * long range a gentle trend rather than a runaway.
 */
function generateHistory(now: number): RawTick[] {
  const out: RawTick[] = [{ ts: now, price: MEAN }]
  let v = MEAN
  let prev = 0
  for (const seg of SEGMENTS) {
    for (let ago = prev + seg.dt; ago <= seg.backTo; ago += seg.dt) {
      // Cap how fast volatility grows with the step so coarse (multi-day) points
      // read as a gentle trend instead of violent noise — a random walk sampled
      // sparsely would jump ±$18/step. Intraday steps (< 1h) are untouched.
      const effDt = Math.min(seg.dt, 3600)
      v += (Math.random() - 0.5) * PRICE_VOL * Math.sqrt(effDt)
      v += (MEAN - v) * REVERT * effDt
      v = Math.max(40, Math.min(180, v))
      out.push({ ts: now - ago, price: v })
    }
    prev = seg.backTo
  }
  return out.reverse() // oldest → newest
}

/** Pretend the full history is fetched from an API (with latency). */
function fetchHistory(): Promise<RawTick[]> {
  return new Promise((resolve) => {
    setTimeout(() => resolve(generateHistory(Date.now() / 1000)), 900)
  })
}

export interface UseDataResult<T> {
  data: T | undefined
  isLoading: boolean
  error: Error | undefined
}

export interface UseDataOptions<T> {
  /** Transform the raw payload (à la React Query's `select`), e.g. into LivelinePoint[]. */
  select?: (raw: RawTick[]) => T
}

/**
 * A tiny React-Query-style data hook (mocked). Fetches the whole history once on
 * mount and exposes `{ data, isLoading }` — switching timeframe never refetches,
 * so it stays instant. `select` maps the raw payload (e.g. into LivelinePoint[]).
 */
export function useData<T = RawTick[]>(options?: UseDataOptions<T>): UseDataResult<T> {
  const select = options?.select
  const [state, setState] = useState<UseDataResult<T>>({
    data: undefined,
    isLoading: true,
    error: undefined,
  })

  useEffect(() => {
    let alive = true
    fetchHistory()
      .then((raw) => {
        if (!alive) return
        setState({ data: (select ? select(raw) : raw) as T, isLoading: false, error: undefined })
      })
      .catch((error: Error) => {
        if (alive) setState((s) => ({ ...s, isLoading: false, error }))
      })
    return () => {
      alive = false
    }
    // Fetch once on mount; `select` is applied to the result, not a dependency.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return state
}

/** Maps the raw API payload into the chart's LivelinePoint shape. */
export function formatData(raw: RawTick[]): LivelinePoint[] {
  return raw.map((tick) => ({ time: tick.ts, value: tick.price }))
}

/**
 * Resample `source` into `n` EVENLY-SPACED points across the last `windowSecs`,
 * linearly interpolating. This is the key to a clean multi-timeframe chart: a
 * 4Y view gets ~n coarse points spanning 4 years (smooth, no dense tail), a 30M
 * view gets ~n fine points spanning 30 minutes — both sampled from the same
 * underlying series, so switching stays coherent. You never load 4 years of
 * fine ticks; you load one interval's worth at that interval's resolution.
 */
export function resampleUniform(
  source: LivelinePoint[],
  windowSecs: number,
  n: number,
  nowSec: number,
): LivelinePoint[] {
  if (source.length === 0) return []
  const start = nowSec - windowSecs
  const out: LivelinePoint[] = new Array(n)
  let j = 0
  for (let i = 0; i < n; i++) {
    const t = start + (windowSecs * i) / (n - 1)
    while (j < source.length - 2 && source[j + 1]!.time < t) j++
    const a = source[j]!
    const b = source[j + 1] ?? a
    const span = b.time - a.time
    const frac = span > 0 ? Math.max(0, Math.min(1, (t - a.time) / span)) : 0
    out[i] = { time: t, value: a.value + (b.value - a.value) * frac }
  }
  return out
}
