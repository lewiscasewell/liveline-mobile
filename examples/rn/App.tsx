import { useEffect, useRef, useState } from 'react'
import { Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native'
import { callback } from 'react-native-nitro-modules'
import { Liveline, type LivelinePoint } from 'react-native-liveline-mobile'
import { INTERVALS, useCandles } from './useData'

export default function App() {
  // The selected interval, and its bars from the (mock) API. Switching refetches
  // — the loader shows on a cache miss, and cached intervals return instantly.
  const [interval, changeInterval] = useState(INTERVALS[4]!) // 1D
  const { data, isLoading } = useCandles(interval)

  // The native chart, captured via hybridRef, for the live feed.
  const chart = useRef<{ push: (point: LivelinePoint) => void } | null>(null)

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
      v += (Math.random() - 0.5) * 0.3 + (v0 - v) * 0.04
      chart.current?.push({ time: Date.now() / 1000, value: v })
      timer = setTimeout(tick, 200 + Math.random() * 2000)
    }
    tick()
    return () => clearTimeout(timer)
  }, [isLoading, data])

  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>Liveline · Nitro</Text>

      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.barScroll}
        contentContainerStyle={styles.bar}
      >
        {INTERVALS.map((iv) => {
          const active = iv.label === interval.label
          return (
            <Pressable
              key={iv.label}
              onPress={() => changeInterval(iv)}
              style={[styles.chip, active && styles.chipActive]}
            >
              <Text style={[styles.chipLabel, active && styles.chipLabelActive]}>{iv.label}</Text>
            </Pressable>
          )
        })}
      </ScrollView>

      <View style={styles.card}>
        <Liveline
          style={styles.chart}
          data={data}
          window={interval.seconds}
          loading={isLoading}
          color="#AB9FF2"
          theme="light"
          surfaceColor="#f9f4ff"
          grid
          fill
          scrub
          showValue
          valueMomentumColor
          momentum="auto"
          pulse={interval.live}
          valuePrefix="$"
          valueDecimals={2}
          hybridRef={callback((ref) => {
            chart.current = ref
          })}
        />
      </View>

      <Text style={styles.caption}>
        {isLoading ? `Loading ${interval.label}…` : `${interval.label} · streaming live`}
      </Text>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#fff', padding: 20, gap: 12 },
  title: { fontSize: 28, fontWeight: '700' },
  card: { height: 300, overflow: 'hidden', backgroundColor: '#f4ebff' },
  chart: { flex: 1 },
  caption: { fontSize: 13, color: '#666' },
  barScroll: { flexGrow: 0 },
  bar: { flexDirection: 'row', gap: 6, alignItems: 'center', paddingRight: 20 },
  chip: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: 999, backgroundColor: '#eee' },
  chipActive: { backgroundColor: '#AB9FF2' },
  chipLabel: { fontSize: 13, fontWeight: '600', color: '#555' },
  chipLabelActive: { color: '#fff' },
})
