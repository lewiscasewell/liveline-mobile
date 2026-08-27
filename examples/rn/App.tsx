import * as React from 'react'
import { useEffect, useMemo, useState } from 'react'
import {
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native'
import { Liveline, useLiveline, type LivelinePoint } from 'liveline-mobile'
import {
  createCandleFeed,
  createCpuFeed,
  createWalk,
  makeBook,
  market,
  MARKET_SERIES,
  type Feed,
} from './feeds'

type DemoProps = { dark: boolean }
type Demo = { id: string; title: string; subtitle: string; Comp: React.FC<DemoProps> }

const themeOf = (dark: boolean) => (dark ? 'dark' : 'light') as 'dark' | 'light'

/**
 * The common case: seed a trending walk, then stream it into the chart via the
 * imperative `push()` (no per-tick React re-render). Returns the backfill seed
 * and the hybridRef to wire the chart to this feed.
 */
function useWalkFeed(make: () => Feed, hz = 15, seedSecs = 45, seedHz = 6) {
  const walk = useMemo(make, [])
  const seed = useMemo(() => walk.seed(seedSecs, seedHz), [walk])
  const { push, attachHybridRef } = useLiveline()
  useEffect(() => {
    const id = setInterval(() => push({ time: Date.now() / 1000, value: walk.step() }), 1000 / hz)
    return () => clearInterval(id)
  }, [walk, push, hz])
  return { seed, attachHybridRef }
}

// ── Demos ────────────────────────────────────────────────────────────────────

const Basic: React.FC<DemoProps> = ({ dark }) => {
  const { seed, attachHybridRef } = useWalkFeed(() => createWalk({ center: 100, vol: 0.55 }))
  return (
    <Liveline
      style={styles.card}
      data={seed}
      momentum='off'
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const Momentum: React.FC<DemoProps> = ({ dark }) => {
  const { seed, attachHybridRef } = useWalkFeed(() => createWalk({ center: 100, vol: 0.7 }))
  return (
    <Liveline
      style={styles.card}
      data={seed}
      momentum='auto'
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const ValueOverlay: React.FC<DemoProps> = ({ dark }) => {
  // Deliberately calm: low vol + high momentum + a slower feed so the big number
  // moves deliberately instead of flickering.
  const { seed, attachHybridRef } = useWalkFeed(
    () => createWalk({ center: 9800, vol: 4, momentum: 0.95, reversion: 0.008 }),
    10,
  )
  return (
    <Liveline
      style={styles.card}
      data={seed}
      showValue
      valueMomentumColor
      valuePrefix='$'
      valueDecimals={2}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const Reference: React.FC<DemoProps> = ({ dark }) => {
  const { seed, attachHybridRef } = useWalkFeed(
    () => createWalk({ center: 67_500, vol: 55, momentum: 0.93 }),
  )
  return (
    <Liveline
      style={styles.card}
      data={seed}
      color='#8b5cf6'
      referenceLine={{ value: 67_500, label: 'Above $67,500' }}
      valuePrefix='$'
      valueDecimals={0}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const HeartRate: React.FC<DemoProps> = ({ dark }) => {
  const { seed, attachHybridRef } = useWalkFeed(
    () => createWalk({ center: 62, vol: 0.3, momentum: 0.8, reversion: 0.02, min: 48, max: 90 }),
  )
  return (
    <Liveline
      style={styles.card}
      data={seed}
      color='#e64d3d'
      exaggerate
      valueSuffix=' bpm'
      valueDecimals={0}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const Cpu: React.FC<DemoProps> = ({ dark }) => {
  const { seed, attachHybridRef } = useWalkFeed(() => createCpuFeed(), 12, 60, 4)
  return (
    <Liveline
      style={styles.card}
      data={seed}
      color='#4aae66'
      window={60}
      valueSuffix='%'
      valueDecimals={0}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const SlowTicker: React.FC<DemoProps> = ({ dark }) => {
  // One update every 4s (a low-volume asset). Native interpolation keeps it
  // scrolling smoothly between ticks.
  const walk = useMemo(() => createWalk({ center: 100, vol: 3.5, momentum: 0.6 }), [])
  const seed = useMemo(() => walk.seed(48, 0.25), [walk])
  const { push, attachHybridRef } = useLiveline()
  useEffect(() => {
    const id = setInterval(() => push({ time: Date.now() / 1000, value: walk.step() }), 4000)
    return () => clearInterval(id)
  }, [walk, push])
  return (
    <Liveline
      style={styles.card}
      data={seed}
      color='#8b5cf6'
      window={60}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const TimeWindows: React.FC<DemoProps> = ({ dark }) => {
  // Seed a full 5m of history so the widest window opens populated, not empty.
  const walk = useMemo(
    () => createWalk({ center: 87, vol: 0.6, min: 55, max: 99 }),
    [],
  )
  const seed = useMemo(() => walk.seed(300, 6), [walk])
  const { push, attachHybridRef } = useLiveline()
  useEffect(() => {
    const id = setInterval(() => push({ time: Date.now() / 1000, value: walk.step() }), 1000 / 15)
    return () => clearInterval(id)
  }, [walk, push])
  return (
    <Liveline
      style={styles.card}
      data={seed}
      color='#f2990f'
      window={60}
      windows={[
        { label: '30s', secs: 30 },
        { label: '1m', secs: 60 },
        { label: '5m', secs: 300 },
      ]}
      windowStyle='rounded'
      valueSuffix='%'
      valueDecimals={0}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const Candlestick: React.FC<DemoProps> = ({ dark }) => {
  const feed = useMemo(() => createCandleFeed(), [])
  const initial = useMemo(() => feed.seed(), [feed])
  const stateRef = React.useRef(initial)
  const [, force] = useState(0)
  const [candle, setCandle] = useState(true)
  const { push, attachHybridRef } = useLiveline()
  // The line source for the morph (and line mode): candle closes, then live ticks.
  const seed = useMemo<LivelinePoint[]>(
    () => initial.candles.map((c) => ({ time: c.time + feed.width, value: c.close })),
    [initial, feed],
  )
  useEffect(() => {
    const id = setInterval(() => {
      stateRef.current = feed.step(stateRef.current.candles, stateRef.current.live)
      push({ time: Date.now() / 1000, value: stateRef.current.live.close })
      force((n) => n + 1)
    }, 1000 / 15)
    return () => clearInterval(id)
  }, [feed, push])
  const { candles, live } = stateRef.current
  return (
    <View style={styles.stack}>
      <View style={styles.toggleRow}>
        {(['Line', 'Candle'] as const).map((label, idx) => {
          const on = candle === (idx === 1)
          return (
            <TouchableOpacity
              key={label}
              onPress={() => setCandle(idx === 1)}
              style={[styles.seg, on && styles.segOn]}
            >
              <Text style={[styles.segText, on && styles.segTextOn]}>{label}</Text>
            </TouchableOpacity>
          )
        })}
      </View>
      <Liveline
        style={styles.card}
        data={seed}
        mode={candle ? 'candle' : 'line'}
        candles={candles.map((c) => ({ time: c.time, open: c.open, high: c.high, low: c.low, close: c.close }))}
        liveCandle={{ time: live.time, open: live.open, high: live.high, low: live.low, close: live.close }}
        candleWidth={feed.width}
        theme={themeOf(dark)}
        hybridRef={attachHybridRef()}
      />
    </View>
  )
}

const Prediction: React.FC<DemoProps> = ({ dark }) => {
  const { push, attachHybridRef } = useLiveline()
  const series = useMemo(() => {
    const now = Date.now() / 1000
    const window = 45
    const n = 160
    return MARKET_SERIES.map((def) => ({
      id: def.id,
      color: def.color,
      label: def.label,
      data: Array.from({ length: n }, (_, i): LivelinePoint => {
        const t = now - window + (i / (n - 1)) * window
        return { time: t, value: market(t)[def.id]! }
      }),
    }))
  }, [])
  useEffect(() => {
    const id = setInterval(() => {
      const t = Date.now() / 1000
      const m = market(t)
      for (const def of MARKET_SERIES) push({ time: t, value: m[def.id]! }, def.id)
    }, 100)
    return () => clearInterval(id)
  }, [push])
  return (
    <Liveline
      style={styles.card}
      series={series}
      window={45}
      valueSuffix='%'
      valueDecimals={0}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const Orderbook: React.FC<DemoProps> = ({ dark }) => {
  const walk = useMemo(() => createWalk({ center: 62, vol: 0.45 }), [])
  const seed = useMemo(() => walk.seed(45, 6), [walk])
  const { push, pushOrderbook, attachHybridRef } = useLiveline()
  useEffect(() => {
    const id = setInterval(() => {
      const price = walk.step()
      push({ time: Date.now() / 1000, value: price })
      pushOrderbook(makeBook(price))
    }, 120)
    return () => clearInterval(id)
  }, [walk, push, pushOrderbook])
  return (
    <Liveline
      style={styles.card}
      data={seed}
      valueSuffix='¢'
      valueDecimals={0}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const Degen: React.FC<DemoProps> = ({ dark }) => {
  const { seed, attachHybridRef } = useWalkFeed(
    () => createWalk({ center: 420, vol: 3 }),
  )
  return (
    <Liveline
      style={styles.card}
      data={seed}
      color='#f5731f'
      momentum='auto'
      degen
      badgeVariant='accent'
      valueDecimals={2}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const Loading: React.FC<DemoProps> = ({ dark }) => {
  const { seed, attachHybridRef } = useWalkFeed(() => createWalk({ center: 210, vol: 0.9 }))
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    const id = setTimeout(() => setLoading(false), 3000)
    return () => clearTimeout(id)
  }, [])
  return (
    <Liveline
      style={styles.card}
      data={seed}
      color='#4aae66'
      loading={loading}
      theme={themeOf(dark)}
      hybridRef={attachHybridRef()}
    />
  )
}

const Paused: React.FC<DemoProps> = ({ dark }) => {
  const { seed, attachHybridRef } = useWalkFeed(() => createWalk({ center: 160, vol: 0.7 }))
  const [paused, setPaused] = useState(false)
  useEffect(() => {
    const id = setInterval(() => setPaused((p) => !p), 4000)
    return () => clearInterval(id)
  }, [])
  return (
    <View style={styles.stack}>
      <Text style={styles.pausedLabel}>{paused ? '⏸ Paused' : '▶ Playing'}</Text>
      <Liveline
        style={styles.card}
        data={seed}
        color='#4aae66'
        paused={paused}
        theme={themeOf(dark)}
        hybridRef={attachHybridRef()}
      />
    </View>
  )
}

const Stale: React.FC<DemoProps> = ({ dark }) => {
  const walk = useMemo(() => createWalk({ center: 100, vol: 0.6 }), [])
  const seed = useMemo(() => walk.seed(45, 6), [walk])
  const { push, attachHybridRef } = useLiveline()
  useEffect(() => {
    const start = Date.now()
    const id = setInterval(() => {
      if (Date.now() - start > 6000) return // feed goes stale after 6s
      push({ time: Date.now() / 1000, value: walk.step() })
    }, 1000 / 15)
    return () => clearInterval(id)
  }, [walk, push])
  return (
    <Liveline style={styles.card} data={seed} theme={themeOf(dark)} hybridRef={attachHybridRef()} />
  )
}

const DEMOS: Demo[] = [
  { id: 'basic', title: 'Basic', subtitle: 'A live value. Two props: data and value.', Comp: Basic },
  { id: 'momentum', title: 'Momentum', subtitle: 'Directional chevrons on the live dot; the badge tints green up / red down.', Comp: Momentum },
  { id: 'value', title: 'Value overlay', subtitle: 'showValue draws the live number over the chart; valueMomentumColor tints it.', Comp: ValueOverlay },
  { id: 'reference', title: 'Reference line', subtitle: 'A horizontal marker at a fixed value, kept in view.', Comp: Reference },
  { id: 'heart', title: 'Heart rate', subtitle: 'exaggerate tightens the Y-axis so tiny moves fill the height.', Comp: HeartRate },
  { id: 'cpu', title: 'CPU usage', subtitle: 'A low idle baseline with occasional spikes.', Comp: Cpu },
  { id: 'sparse', title: 'Slow ticker', subtitle: 'One update every 4s. It still scrolls smoothly between ticks.', Comp: SlowTicker },
  { id: 'windows', title: 'Time windows', subtitle: 'Tap 30s / 1m / 5m to smoothly zoom the interval over 5 minutes of history.', Comp: TimeWindows },
  { id: 'candles', title: 'Candlestick', subtitle: 'OHLC candles with a live candle that grows its wicks. Toggle line / candle.', Comp: Candlestick },
  { id: 'prediction', title: 'Prediction market', subtitle: 'Multi-series: three outcomes summing to 100%. Tap a chip to toggle a line.', Comp: Prediction },
  { id: 'orderbook', title: 'Orderbook', subtitle: 'Bid/ask sizes float up behind the price line — green bids, red asks.', Comp: Orderbook },
  { id: 'degen', title: 'Degen', subtitle: 'Chart shake + sparks on strong up-moves, with momentum arrows.', Comp: Degen },
  { id: 'loading', title: 'Loading', subtitle: 'A breathing line for 3s, then it morphs into the backfilled chart.', Comp: Loading },
  { id: 'paused', title: 'Paused', subtitle: 'Auto-toggles every 4s. Data keeps arriving; on resume it catches up.', Comp: Paused },
  { id: 'stale', title: 'Stale feed', subtitle: 'The feed stops after 6s. The chart keeps scrolling; the line runs flat.', Comp: Stale },
]

/** A dropdown (menu) picker for the demo, mirroring the native `.menu` Picker. */
const DemoPicker: React.FC<{
  dark: boolean
  value: string
  onChange: (id: string) => void
}> = ({ dark, value, onChange }) => {
  const [open, setOpen] = useState(false)
  const current = DEMOS.find((d) => d.id === value)!
  return (
    <>
      <TouchableOpacity
        style={[styles.dropdown, dark ? styles.dropdownDark : styles.dropdownLight]}
        onPress={() => setOpen(true)}
      >
        <Text style={[styles.dropdownText, dark ? styles.textLight : styles.textDark]}>
          {current.title}
        </Text>
        <Text style={[styles.dropdownChevron, dark ? styles.textDim : styles.textDimLight]}>▾</Text>
      </TouchableOpacity>
      <Modal visible={open} transparent animationType='fade' onRequestClose={() => setOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setOpen(false)}>
          <View style={[styles.menu, dark ? styles.menuDark : styles.menuLight]}>
            <ScrollView bounces={false}>
              {DEMOS.map((d) => {
                const on = d.id === value
                return (
                  <TouchableOpacity
                    key={d.id}
                    style={styles.menuItem}
                    onPress={() => {
                      onChange(d.id)
                      setOpen(false)
                    }}
                  >
                    <Text
                      style={[
                        styles.menuItemText,
                        dark ? styles.textLight : styles.textDark,
                        on && styles.menuItemOn,
                      ]}
                    >
                      {d.title}
                    </Text>
                    {on && <Text style={styles.menuCheck}>✓</Text>}
                  </TouchableOpacity>
                )
              })}
            </ScrollView>
          </View>
        </Pressable>
      </Modal>
    </>
  )
}

export default function App() {
  const [dark, setDark] = useState(true)
  const [selectedId, setSelectedId] = useState(DEMOS[0]!.id)
  const demo = DEMOS.find((d) => d.id === selectedId)!

  return (
    <View style={[styles.root, { paddingTop: TOP_INSET }, dark ? styles.rootDark : styles.rootLight]}>
      <View style={styles.header}>
        <Text style={[styles.title, dark ? styles.textLight : styles.textDark]}>Liveline</Text>
        <View style={styles.toggleRow}>
          {([['Light', false], ['Dark', true]] as const).map(([label, val]) => {
            const on = dark === val
            return (
              <TouchableOpacity
                key={label}
                onPress={() => setDark(val)}
                style={[styles.seg, on && styles.segOn]}
              >
                <Text style={[styles.segText, on && styles.segTextOn]}>{label}</Text>
              </TouchableOpacity>
            )
          })}
        </View>
      </View>

      <DemoPicker dark={dark} value={selectedId} onChange={setSelectedId} />

      {/* key remounts the demo (fresh feed) when the selection changes */}
      <View key={demo.id} style={styles.demoArea}>
        <demo.Comp dark={dark} />
      </View>
      <Text style={[styles.subtitle, dark ? styles.textDim : styles.textDimLight]}>{demo.subtitle}</Text>
    </View>
  )
}

// A safe top inset without pulling in react-native-safe-area-context: the status
// bar height on Android, a notch-friendly constant on iOS.
const TOP_INSET = Platform.OS === 'android' ? (StatusBar.currentHeight ?? 24) + 8 : 56

const styles = StyleSheet.create({
  root: { flex: 1, padding: 20, gap: 14 },
  rootDark: { backgroundColor: '#0a0a0a' },
  rootLight: { backgroundColor: '#f4f5f7' },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  title: { fontSize: 30, fontWeight: '700' },
  dropdown: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 12,
  },
  dropdownDark: { backgroundColor: '#1c1c1e' },
  dropdownLight: { backgroundColor: '#e5e7eb' },
  dropdownText: { fontSize: 16, fontWeight: '600' },
  dropdownChevron: { fontSize: 14 },
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.4)', justifyContent: 'center', padding: 24 },
  menu: { borderRadius: 14, maxHeight: '70%', overflow: 'hidden' },
  menuDark: { backgroundColor: '#1c1c1e' },
  menuLight: { backgroundColor: '#fff' },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 18,
    paddingVertical: 14,
  },
  menuItemText: { fontSize: 16 },
  menuItemOn: { fontWeight: '700', color: '#3b82f6' },
  menuCheck: { fontSize: 16, color: '#3b82f6', fontWeight: '700' },
  demoArea: { marginTop: 4 },
  card: { height: 320 },
  stack: { gap: 10 },
  toggleRow: { flexDirection: 'row', gap: 6 },
  seg: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: 8, backgroundColor: '#1c1c1e' },
  segOn: { backgroundColor: '#3b82f6' },
  segText: { color: '#9ca3af', fontSize: 13, fontWeight: '600' },
  segTextOn: { color: '#fff' },
  subtitle: { fontSize: 13, lineHeight: 18 },
  pausedLabel: { fontSize: 13, fontFamily: 'monospace', color: '#9ca3af' },
  textLight: { color: '#fff' },
  textDark: { color: '#111' },
  textDim: { color: '#8a8a8e' },
  textDimLight: { color: '#6b7280' },
})
