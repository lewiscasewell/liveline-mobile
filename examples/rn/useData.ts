import { useEffect, useState } from 'react'
import type { LivelinePoint } from 'liveline-mobile'

/**
 * A selectable interval — just a label and a visible span in seconds.
 */
export type Interval = { label: string; seconds: number; live?: boolean }

const DAY = 86400

export const INTERVALS: Interval[] = [
  // { label: '4Y', seconds: 4 * 365 * DAY },
  // { label: '1Y', seconds: 365 * DAY },
  { label: '1M', seconds: 30 * DAY },
  { label: '1W', seconds: 7 * DAY },
  { label: '1D', seconds: DAY },
  { label: '4H', seconds: 4 * 3600 },
  { label: '1H', seconds: 3600 },
  { label: '30M', seconds: 1800 },
  { label: 'Live', seconds: 60, live: true },
]

/** Every interval returns the same number of points — its own resolution. */
const POINTS = 200

// ─────────────────────────────────────────────────────────────────────────────
// Everything below simulates a BACKEND. A real app would call its API here; the
// consumer (App.tsx) never sees any of this — it just gets `{ data, isLoading }`.
// ─────────────────────────────────────────────────────────────────────────────

type RawTick = { ts: number; price: number }

const MEAN = 100
const VOL = 0.02 // per √second
const REVERT = 4e-7

/** The "server's" full-resolution history, generated once. */
let masterCache: RawTick[] | null = null

function master(now: number): RawTick[] {
  if (!masterCache) masterCache = generateMaster(now)
  return masterCache
}

/** A mean-reverting walk sampled fine recently, coarse long ago (~1k points). */
function generateMaster(now: number): RawTick[] {
  const segments = [
    { backTo: 1800, dt: 20 },
    { backTo: 4 * 3600, dt: 120 },
    { backTo: DAY, dt: 900 },
    { backTo: 7 * DAY, dt: 2 * 3600 },
    { backTo: 30 * DAY, dt: 12 * 3600 },
    { backTo: 365 * DAY, dt: 2 * DAY },
    { backTo: 4 * 365 * DAY, dt: 10 * DAY },
  ]
  const out: RawTick[] = [{ ts: now, price: MEAN }]
  let v = MEAN
  let prev = 0
  for (const seg of segments) {
    for (let ago = prev + seg.dt; ago <= seg.backTo; ago += seg.dt) {
      // Cap volatility growth past 1h so multi-day points read as a gentle trend.
      const effDt = Math.min(seg.dt, 3600)
      v += (Math.random() - 0.5) * VOL * Math.sqrt(effDt)
      v += (MEAN - v) * REVERT * effDt
      v = Math.max(40, Math.min(180, v))
      out.push({ ts: now - ago, price: v })
    }
    prev = seg.backTo
  }
  return out.reverse()
}

/** Resample the master into `n` evenly-spaced points across the last window. */
function resample(source: RawTick[], windowSecs: number, n: number, now: number): LivelinePoint[] {
  const start = now - windowSecs
  const out: LivelinePoint[] = new Array(n)
  let j = 0
  for (let i = 0; i < n; i++) {
    const t = start + (windowSecs * i) / (n - 1)
    while (j < source.length - 2 && source[j + 1]!.ts < t) j++
    const a = source[j]!
    const b = source[j + 1] ?? a
    const span = b.ts - a.ts
    const frac = span > 0 ? Math.max(0, Math.min(1, (t - a.ts) / span)) : 0
    out[i] = { time: t, value: a.price + (b.price - a.price) * frac }
  }
  return out
}

/** Simulated API call: the bars for one interval, at that interval's resolution. */
function fetchInterval(interval: Interval): Promise<LivelinePoint[]> {
  return new Promise((resolve) => {
    setTimeout(() => {
      const now = Date.now() / 1000
      resolve(resample(master(now), interval.seconds, POINTS, now))
    }, 700) // network latency
  })
}

/** Per-interval result cache — like React Query. Returning to a fetched interval is instant. */
const cache = new Map<string, LivelinePoint[]>()

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fetch the bars for an interval — the ONLY data hook the app uses. Refetches
 * when the interval changes (loader shows on a cache miss, e.g. loading more
 * history), and serves a cached interval instantly. Keeps the previous data
 * visible while loading so the chart morphs old → loading → new.
 */
export function useCandles(interval: Interval): {
  data: LivelinePoint[] | undefined
  isLoading: boolean
} {
  const [state, setState] = useState<{ data: LivelinePoint[] | undefined; isLoading: boolean }>(
    () => {
      const cached = cache.get(interval.label)
      return { data: cached, isLoading: !cached }
    },
  )

  useEffect(() => {
    let alive = true
    const cached = cache.get(interval.label)
    if (cached) {
      setState({ data: cached, isLoading: false })
      return
    }
    setState((s) => ({ data: s.data, isLoading: true })) // keep old data visible while loading
    fetchInterval(interval).then((data) => {
      if (!alive) return
      cache.set(interval.label, data)
      setState({ data, isLoading: false })
    })
    return () => {
      alive = false
    }
  }, [interval])

  return state
}
