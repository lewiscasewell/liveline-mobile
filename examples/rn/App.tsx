import { useEffect, useMemo, useState } from 'react'
import { SafeAreaView, StyleSheet, Text } from 'react-native'
import { Liveline, useLiveline } from 'liveline-mobile'
import { INTERVALS, useCandles } from './useData'

const WINDOWS = INTERVALS.map((i) => ({ label: i.label, secs: i.seconds }))

export default function App() {
  // The selected interval, and its bars from the (mock) API. Switching refetches
  // — the loader shows on a cache miss, and cached intervals return instantly.
  const [interval, changeInterval] = useState(INTERVALS[4]!) // 1D
  const [mode, setMode] = useState<'line' | 'candle'>('line')
  const { data, isLoading } = useCandles(interval)

  // Aggregate the line points into OHLC candles for candle mode (every 4 points).
  const candles = useMemo(() => {
    if (!data) return []
    const out = []
    for (let i = 0; i < data.length; i += 4) {
      const g = data.slice(i, i + 4)
      if (g.length === 0) break
      const v = g.map((p) => p.value)
      out.push({
        time: g[0]!.time,
        open: v[0]!,
        high: Math.max(...v),
        low: Math.min(...v),
        close: v[v.length - 1]!,
      })
    }
    return out
  }, [data])

  // useLiveline owns the ref + push — no hybridRef/callback plumbing here.
  const { attachHybridRef, push } = useLiveline()

  // Live feed: just push ticks. The chart buckets them to the current window
  // automatically — dense on Live, a sliding head on 4Y — so this stays a dumb
  // loop with no per-interval bookkeeping. React never re-renders on the feed.
  useEffect(() => {
    if (isLoading || !data || data.length === 0) return
    const v0 = data[data.length - 1]!.value
    let v = v0
    let timer: ReturnType<typeof setTimeout>
    const tick = () => {
      // Small, mean-reverting steps so the live value stays near the historical
      // scale — otherwise it drifts far and, on a wide window where seconds are
      // sub-pixel, renders as a harsh vertical spike. The Live view still looks
      // lively because auto-range fills the frame with whatever movement there is.
      v += (Math.random() - 0.5) * 0.2 + (v0 - v) * 0.008
      push({ time: Date.now() / 1000, value: v })
      timer = setTimeout(tick, 200 + Math.random() * 2000)
    }
    tick()
    return () => clearTimeout(timer)
  }, [isLoading, data, push])

  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>Liveline · Nitro</Text>

      <Liveline
        style={styles.card}
        // The built-in interval bar (web-liveline parity): the library renders
        // the buttons and reports the chosen span; we just refetch on change.
        windows={WINDOWS}
        window={interval.seconds}
        windowStyle='rounded'
        onWindowChange={(secs) => {
          const next = INTERVALS.find((i) => i.seconds === secs)
          if (next) changeInterval(next)
        }}
        // Optional line/candle toggle at the end of the bar.
        mode={mode}
        candles={candles}
        candleWidth={interval.seconds / Math.max(candles.length, 1)}
        onModeChange={setMode}
        data={data}
        loading={isLoading}
        badge={true}
        color="#AB9FF2"
        theme="light"
        showValue
        haptics
        degen
        momentum="auto"
        badgeVariant="minimal"
        pulse={interval.live}
        valuePrefix="$"
        valueDecimals={2}
        hybridRef={attachHybridRef()}
      />

      <Text style={styles.caption}>
        {isLoading ? `Loading ${interval.label}…` : `${interval.label} · streaming live`}
      </Text>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#fff', padding: 20, gap: 12 },
  title: { fontSize: 28, fontWeight: '700' },
  card: { height: 348 },
  caption: { fontSize: 13, color: '#666' },
})
