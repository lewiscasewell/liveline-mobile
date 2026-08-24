import { useEffect, useRef, useState } from 'react'
import { Pressable, SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native'
import { callback } from 'react-native-nitro-modules'
import { Liveline, type LivelinePoint } from 'react-native-liveline-mobile'
import { formatData, MEAN, PRICE_VOL, resampleUniform, TIMEFRAMES, useData } from './useData'
import { Button } from 'react-native'

// Points per view. Every timeframe renders this many EVENLY-SPACED samples, so
// density is uniform at every zoom — a 4Y view is ~160 coarse points (a smooth
// trend), a 30M view ~160 fine ones (the live head adds finer detail still).
// Also sets the live commit resolution (span ÷ this).
const VIEW_POINTS = 160

export default function App() {
  // The native view instance, captured via hybridRef. The live feed calls
  // methods on this directly — no React state, no re-renders.
  const chart = useRef<{
    push: (point: LivelinePoint) => void
    updateHead: (point: LivelinePoint) => void
  } | null>(null)

  // The selected timeframe. Default to 1D so the first load shows a full day.
  const [tfIndex, setTfIndex] = useState(4)
  const tf = TIMEFRAMES[tfIndex]!

  // Fetch the full-resolution "truth" once through a React-Query-style hook.
  // We never hand this straight to the chart — it's the master series we
  // resample per timeframe.
  const { data, isLoading } = useData({ select: formatData })

  // The master series (grows as live ticks arrive) and the uniform slice we
  // actually render for the current timeframe.
  const master = useRef<LivelinePoint[]>([])
  const [view, setView] = useState<LivelinePoint[] | undefined>(undefined)
  const last = useRef(MEAN)

  // Seed the master from the loaded history, once.
  useEffect(() => {
    if (!isLoading && data && master.current.length === 0) {
      master.current = data.slice()
      last.current = data[data.length - 1]?.value ?? MEAN
    }
  }, [isLoading, data])

  // Resample a uniform view whenever the timeframe changes. A settled view is
  // ~VIEW_POINTS evenly-spaced points at that interval's resolution.
  //
  // The trick for a smooth zoom is to NEVER swap coarse↔fine mid-transition —
  // that snaps the line's smoothness. Instead, during the ~750ms window zoom we
  // feed ONE finer-resolution slice spanning the WIDER of the two windows, and
  // let the native's per-frame decimation morph the smoothness continuously:
  // zooming in, points progressively un-decimate into detail; zooming out, they
  // progressively decimate away. Once the zoom lands we settle to the target's
  // own resolution — invisible, because over the visible window the density is
  // already the same (it just trims the now-offscreen span).
  const prevWindow = useRef(tf.seconds)
  useEffect(() => {
    if (isLoading || master.current.length === 0) return
    const oldW = prevWindow.current
    const newW = tf.seconds
    prevWindow.current = newW

    if (oldW === newW) {
      setView(resampleUniform(master.current, newW, VIEW_POINTS, Date.now() / 1000))
      return
    }

    const widerW = Math.max(oldW, newW)
    const narrowerW = Math.min(oldW, newW)
    // Enough points that the target window still holds ~VIEW_POINTS, capped so a
    // big ratio (e.g. 30M↔Live) can't over-feed.
    const n = Math.min(1500, Math.round(VIEW_POINTS * (widerW / narrowerW)))
    setView(resampleUniform(master.current, widerW, n, Date.now() / 1000))

    const t = setTimeout(() => {
      setView(resampleUniform(master.current, newW, VIEW_POINTS, Date.now() / 1000))
    }, 820)
    return () => clearTimeout(t)
  }, [tf, isLoading])

  // The feed always runs — real-time data draws on in every timeframe, at that
  // interval's resolution. We COMMIT a new point once per bucket (span ÷ points)
  // to both the native chart and the master, and slide the live head between
  // commits with updateHead(). So the tail repaints at the view's own
  // resolution instead of piling ticks onto "now".
  useEffect(() => {
    if (isLoading || master.current.length === 0) return
    const bucket = tf.seconds / VIEW_POINTS
    let lastCommit = 0
    let timer: ReturnType<typeof setTimeout>
    const tick = () => {
      // √-scale the step by the gap with the master's volatility, so streamed
      // ticks share its texture (no jagged spike at any zoom).
      const gap = 0.1 + Math.random() * 0.9
      const step = (Math.random() - 0.5) * 3.46 * PRICE_VOL * Math.sqrt(gap)
      last.current += step + (MEAN - last.current) * 0.003
      const now = Date.now() / 1000
      const point = { time: now, value: last.current }
      if (now - lastCommit >= bucket) {
        chart.current?.push(point) // open a new bucket
        master.current.push(point)
        lastCommit = now
      } else {
        chart.current?.updateHead(point) // slide the forming head
        master.current[master.current.length - 1] = point
      }
      timer = setTimeout(tick, gap * 1000)
    }
    tick()
    return () => clearTimeout(timer)
  }, [tf, isLoading])

  const doThing = () => {
    chart.current?.push({ time: Date.now() / 1000, value: 102 })
  }

  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>Liveline · Nitro</Text>

      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.windowScroll}
        contentContainerStyle={styles.windowRow}
      >
        {TIMEFRAMES.map((t, i) => {
          const active = i === tfIndex
          return (
            <Pressable
              key={t.label}
              onPress={() => setTfIndex(i)}
              style={[styles.windowChip, active && styles.windowChipActive]}
            >
              <Text style={[styles.windowLabel, active && styles.windowLabelActive]}>
                {t.label}
              </Text>
            </Pressable>
          )
        })}
      </ScrollView>

      <View style={styles.card}>
        <Liveline
          style={styles.chart}
          data={view}
          loading={isLoading}
          color="#AB9FF2"
          theme="light"
          surfaceColor="#f4ebff"
          lineWidth={2}
          grid
          fill
          pulse={tf.live}
          momentum="auto"
          showValue
          valueMomentumColor
          scrub
          window={tf.seconds}
          valuePrefix="$"
          valueDecimals={2}
          hybridRef={callback((ref) => {
            chart.current = ref
          })}
        />
      </View>

      <Text style={styles.caption}>
        {isLoading
          ? 'Loading history from useData()…'
          : `${tf.label} view — ${VIEW_POINTS} evenly-spaced points at ${tf.label} resolution, resampled from one series. Live head commits per bucket.`}
      </Text>

      <Button title="do thing" onPress={doThing} />
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#fff', padding: 20, gap: 12 },
  title: { fontSize: 28, fontWeight: '700' },
  card: { height: 300, overflow: 'hidden', backgroundColor: '#f4ebff' },
  chart: { flex: 1 },
  caption: { fontSize: 13, color: '#666' },
  windowScroll: { flexGrow: 0 },
  windowRow: { flexDirection: 'row', gap: 6, alignItems: 'center', paddingRight: 20 },
  windowChip: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: '#eee',
  },
  windowChipActive: { backgroundColor: '#AB9FF2' },
  windowLabel: { fontSize: 13, fontWeight: '600', color: '#555' },
  windowLabelActive: { color: '#fff' },
})
