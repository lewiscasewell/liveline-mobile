import { useFonts } from 'expo-font'
import { useEffect, useMemo, useState } from 'react'
import { SafeAreaView, StyleSheet, Text } from 'react-native'
import { Liveline, useLiveline } from 'liveline-mobile'
import { INTERVALS, useCandles } from './useData'

const WINDOWS = INTERVALS.map((i) => ({ label: i.label, secs: i.seconds }))

// A mock prediction market: three outcomes that always sum to 100%.
const OUTCOMES = [
  { id: 'yes', color: '#3b82f6', label: 'Yes' },
  { id: 'no', color: '#ef4444', label: 'No' },
  { id: 'maybe', color: '#f59e0b', label: 'Maybe' },
] as const

function market(t: number): Record<string, number> {
  // A slow wave sets the trend; a smaller, faster wave keeps the live head
  // visibly moving without the jagged spikes of a high-frequency signal.
  const yes = 45 + Math.sin(t * 0.006) * 11 + Math.sin(t * 0.021) * 3
  const no = 35 + Math.cos(t * 0.005) * 9 + Math.cos(t * 0.018) * 2.5
  const maybe = 30 + Math.sin(t * 0.004 + 1) * 6 + Math.cos(t * 0.016) * 2
  const sum = yes + no + maybe
  return { yes: (yes / sum) * 100, no: (no / sum) * 100, maybe: (maybe / sum) * 100 }
}

export default function App() {
  // Interval drives the window span + backfill length (from the mock API).
  const [interval, changeInterval] = useState(INTERVALS[4]!)
  const { data, isLoading } = useCandles(interval)

  // Bundled custom font, loaded at runtime (standard Expo pattern, no prebuild).
  const [fontsLoaded] = useFonts({ Inter: require('./assets/fonts/Inter.ttf') })

  // Multi-series: pass `series` instead of `data`/`value`. Each outcome is one
  // line; the legend chips, endpoint dots + labels and hover value-row are all
  // automatic.
  const series = useMemo(
    () =>
      !data
        ? []
        : OUTCOMES.map((o) => ({
            id: o.id,
            color: o.color,
            label: o.label,
            data: data.map((d) => ({ time: d.time, value: market(d.time)[o.id]! })),
          })),
    [data]
  )

  const { attachHybridRef, push } = useLiveline()

  // Live feed: push each outcome once per tick, routed by series id.
  useEffect(() => {
    if (isLoading || !data || data.length === 0) return
    let timer: ReturnType<typeof setTimeout>
    const tick = () => {
      const now = Date.now() / 1000
      const m = market(now)
      for (const o of OUTCOMES) push({ time: now, value: m[o.id]! }, o.id)
      timer = setTimeout(tick, 400 + Math.random() * 1200)
    }
    tick()
    return () => clearTimeout(timer)
  }, [isLoading, data, push])

  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>Liveline · Nitro</Text>

      <Liveline
        style={styles.card}
        windows={WINDOWS}
        window={interval.seconds}
        windowStyle='rounded'
        onWindowChange={(secs) => {
          const next = INTERVALS.find((i) => i.seconds === secs)
          if (next) changeInterval(next)
        }}
        series={series}
        loading={isLoading}
        theme='light'
        fontFamily={fontsLoaded ? 'Inter' : undefined}
        haptics
        valueSuffix='%'
        valueDecimals={0}
        hybridRef={attachHybridRef()}
      />

      <Text style={styles.caption}>
        Prediction market · three outcomes, always summing to 100% · tap a chip to toggle a line
      </Text>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#fff', padding: 20, gap: 12 },
  title: { fontSize: 28, fontWeight: '700' },
  card: { height: 360 },
  caption: { fontSize: 13, color: '#666' },
})
