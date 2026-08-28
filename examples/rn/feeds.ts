import type { LivelinePoint } from 'liveline-mobile'

// ─────────────────────────────────────────────────────────────────────────────
// Realistic feed simulation for the demos.
//
// The key to a lifelike line (matching web liveline) is NOT i.i.d. up/down
// noise — that reads as jittery zig-zag. Instead each feed integrates a
// *velocity* that is itself a slowly-decaying AR(1) process: the direction
// persists for a stretch (mostly up during an up-move, with the odd down-tick),
// occasionally stalls, then reverses. Gentle mean-reversion keeps it bounded.
// ─────────────────────────────────────────────────────────────────────────────

/** Standard normal via Box–Muller — smoother tails than a uniform. */
export function randn(): number {
  let u = 0
  let v = 0
  while (u === 0) u = Math.random()
  while (v === 0) v = Math.random()
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v)
}

export interface WalkOpts {
  center: number
  /** Typical size of a per-step move (≈ the velocity's standard deviation). */
  vol: number
  /**
   * Velocity autocorrelation, 0..1. Higher = longer, smoother trends before a
   * reversal. 0.9 ≈ ~10-step trends; 0.95 ≈ ~20-step trends.
   */
  momentum?: number
  /** Pull back toward `center` each step (keeps the walk bounded). */
  reversion?: number
  /** Positive biases the velocity, trending the walk upward (e.g. degen moon). */
  drift?: number
  min?: number
  max?: number
}

/** The minimal streaming feed: advance a step, or backfill a seed history. */
export interface Feed {
  /** Advance one step and return the new value. */
  step(): number
  /** A backfill history ending at "now" (so the chart opens populated). */
  seed(seconds: number, hz: number): LivelinePoint[]
}

export interface Walk extends Feed {
  readonly value: number
}

export function createWalk(opts: WalkOpts): Walk {
  const { center, vol, momentum = 0.94, reversion = 0.01, drift = 0, min, max } = opts
  // Scale the random kick so the AR(1) velocity's stationary stddev ≈ vol.
  const kick = vol * Math.sqrt(1 - momentum * momentum)
  let value = center
  let velocity = 0

  function step(): number {
    velocity = velocity * momentum + randn() * kick + drift
    value += velocity + (center - value) * reversion
    if (min != null && value < min) {
      value = min
      velocity = Math.abs(velocity) * 0.5
    }
    if (max != null && value > max) {
      value = max
      velocity = -Math.abs(velocity) * 0.5
    }
    return value
  }

  function seed(seconds: number, hz: number): LivelinePoint[] {
    const now = Date.now() / 1000
    const n = Math.max(2, Math.round(seconds * hz))
    const pts: LivelinePoint[] = new Array(n)
    for (let i = 0; i < n; i++) {
      const v = step()
      pts[i] = { time: now - seconds + (i / (n - 1)) * seconds, value: v }
    }
    return pts
  }

  return {
    step,
    seed,
    get value() {
      return value
    },
  }
}

// ── CPU usage: a low idle baseline with occasional decaying spikes ───────────

export interface CpuFeed extends Feed {
  step(): number
  seed(seconds: number, hz: number): LivelinePoint[]
}

export function createCpuFeed(): CpuFeed {
  const base = createWalk({ center: 14, vol: 1.2, momentum: 0.85, reversion: 0.06, min: 2 })
  let spike = 0
  function step(): number {
    const b = base.step()
    if (Math.random() > 0.985) spike = 40 + Math.random() * 35
    spike *= 0.82
    return Math.max(2, Math.min(100, b + spike))
  }
  function seed(seconds: number, hz: number): LivelinePoint[] {
    const now = Date.now() / 1000
    const n = Math.max(2, Math.round(seconds * hz))
    const pts: LivelinePoint[] = new Array(n)
    for (let i = 0; i < n; i++) {
      pts[i] = { time: now - seconds + (i / (n - 1)) * seconds, value: step() }
    }
    return pts
  }
  return { step, seed }
}

// ── Order book: six resting levels each side, sizes jittering each tick ──────

export function makeBook(price: number): {
  bids: [number, number][]
  asks: [number, number][]
} {
  const bids: [number, number][] = []
  const asks: [number, number][] = []
  for (let i = 0; i < 6; i++) {
    const d = i * 0.12 + 0.08
    // Dollar-ish sizes: mostly small orders, the occasional whale.
    const bid = Math.random() > 0.9 ? 80 + Math.random() * 180 : 4 + Math.random() * 66
    const ask = Math.random() > 0.9 ? 80 + Math.random() * 180 : 4 + Math.random() * 66
    bids.push([price - d, bid])
    asks.push([price + d, ask])
  }
  return { bids, asks }
}

// ── Prediction market: three outcomes that always sum to 100% ────────────────

export const MARKET_SERIES = [
  { id: 'yes', color: '#3b82f6', label: 'Yes' },
  { id: 'maybe', color: '#f59e0b', label: 'Maybe' },
  { id: 'no', color: '#ef4444', label: 'No' },
] as const

/**
 * Deterministic in `t`, so the backfill and the live feed line up seamlessly.
 * A realistic lopsided market: Yes leads at ~70–90%, then Maybe, then No.
 */
export function market(t: number): Record<string, number> {
  const yes = 80 + Math.sin(t * 0.18) * 8 + Math.sin(t * 0.6) * 2
  const maybe = 13 + Math.sin(t * 0.22 + 1) * 3
  const no = 7 + Math.cos(t * 0.28) * 2
  const sum = yes + no + maybe
  return { yes: (yes / sum) * 100, no: (no / sum) * 100, maybe: (maybe / sum) * 100 }
}

// ── Stress tests: extreme feeds that exercise the render loop ────────────────

export type StressVariant =
  | 'wild' | 'flatSpikes' | 'chaotic' | 'reversals' | 'isolatedSpikes' | 'zigzag' | 'irregular'

export const STRESS: { id: StressVariant; title: string; detail: string; intervalMs: number; exaggerate: boolean }[] = [
  { id: 'wild', title: 'Wild swings', detail: 'Large continuous swings at 100ms.', intervalMs: 100, exaggerate: false },
  { id: 'flatSpikes', title: 'Near-flat + spikes', detail: 'A near-flat line with sudden spikes (exaggerated Y).', intervalMs: 150, exaggerate: true },
  { id: 'chaotic', title: 'Chaotic', detail: 'Massive fluctuations at 80ms.', intervalMs: 80, exaggerate: false },
  { id: 'reversals', title: 'Sharp reversals', detail: 'Frequent sharp direction reversals at 60ms.', intervalMs: 60, exaggerate: false },
  { id: 'isolatedSpikes', title: 'Isolated spikes', detail: 'Nearly flat with rare extreme spikes (exaggerated Y).', intervalMs: 120, exaggerate: true },
  { id: 'zigzag', title: 'Rapid zigzag', detail: 'Rapid alternating oscillation at 50ms.', intervalMs: 50, exaggerate: false },
  { id: 'irregular', title: 'Irregular arrivals', detail: 'Bursts of updates with random 1–3s stalls.', intervalMs: 60, exaggerate: false },
]

export interface StressFeed extends Feed {
  readonly intervalMs: number
}

/** Mirrors the iOS StressFeed: one chaotic pattern per variant, bounded to 20..180. */
export function createStressFeed(variant: StressVariant): StressFeed {
  const rnd = (a: number, b: number) => a + Math.random() * (b - a)
  let v = 100
  let dir = 1
  let ticks = 0
  let stallUntil = 0
  function step(): number {
    ticks++
    if (variant === 'irregular' && Date.now() < stallUntil) return v
    switch (variant) {
      case 'wild': v += rnd(-8, 8); break
      case 'flatSpikes': v += rnd(-0.3, 0.3); if (Math.random() > 0.95) v += rnd(-25, 25); break
      case 'chaotic': v += rnd(-18, 18); break
      case 'reversals': if (ticks % 6 === 0) dir = -dir; v += dir * rnd(2, 10); break
      case 'isolatedSpikes': v += rnd(-0.2, 0.2); if (Math.random() > 0.97) v += rnd(-40, 40); break
      case 'zigzag': dir = -dir; v += dir * rnd(4, 9); break
      case 'irregular': v += rnd(-6, 6); if (Math.random() < 0.02) stallUntil = Date.now() + rnd(1000, 3000); break
    }
    v = Math.max(20, Math.min(180, v))
    return v
  }
  function seed(seconds: number, hz: number): LivelinePoint[] {
    const now = Date.now() / 1000
    const n = Math.max(2, Math.round(seconds * hz))
    let s = 100
    return Array.from({ length: n }, (_, i) => {
      s += rnd(-3, 3)
      return { time: now - seconds + (i / (n - 1)) * seconds, value: s }
    })
  }
  return { step, seed, intervalMs: STRESS.find((x) => x.id === variant)!.intervalMs }
}

// ── Candles: aggregate a trending price into fixed-width OHLC buckets ─────────

export interface Candle {
  time: number
  open: number
  high: number
  low: number
  close: number
}

export interface CandleFeed {
  readonly width: number
  seed(): { candles: Candle[]; live: Candle }
  /** Advance the price and fold it into the current (or a new) bucket. */
  step(candles: Candle[], live: Candle): { candles: Candle[]; live: Candle }
}

export function createCandleFeed(): CandleFeed {
  const width = 3
  const walk = createWalk({ center: 150, vol: 1.4, momentum: 0.93, reversion: 0.006 })

  function bucketOf(t: number): number {
    return Math.floor(t / width) * width
  }

  function seed(): { candles: Candle[]; live: Candle } {
    const liveBucket = bucketOf(Date.now() / 1000)
    const candles: Candle[] = []
    for (let i = 18; i >= 1; i--) {
      const open = walk.value
      let hi = open
      let lo = open
      let close = open
      for (let k = 0; k < 10; k++) {
        close = walk.step()
        hi = Math.max(hi, close)
        lo = Math.min(lo, close)
      }
      candles.push({ time: liveBucket - width * i, open, high: hi, low: lo, close })
    }
    const p = walk.value
    return { candles, live: { time: liveBucket, open: p, high: p, low: p, close: p } }
  }

  function step(
    candles: Candle[],
    live: Candle,
  ): { candles: Candle[]; live: Candle } {
    const price = walk.step()
    const bucket = bucketOf(Date.now() / 1000)
    if (bucket !== live.time) {
      const next = [...candles, live].slice(-40)
      return { candles: next, live: { time: bucket, open: price, high: price, low: price, close: price } }
    }
    return {
      candles,
      live: {
        ...live,
        high: Math.max(live.high, price),
        low: Math.min(live.low, price),
        close: price,
      },
    }
  }

  return { width, seed, step }
}
