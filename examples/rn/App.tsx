import { useEffect, useMemo } from 'react'
import { SafeAreaView, StyleSheet, Text } from 'react-native'
import { Liveline, useLiveline, type LivelinePoint } from 'liveline-mobile'

// A synthetic order book: six levels each side, sizes jittering each tick.
function makeBook(price: number): { bids: [number, number][]; asks: [number, number][] } {
  const bids: [number, number][] = []
  const asks: [number, number][] = []
  for (let i = 0; i < 6; i++) {
    const d = i * 0.12 + 0.08
    const bid = Math.random() > 0.9 ? 80 + Math.random() * 180 : 4 + Math.random() * 66
    const ask = Math.random() > 0.9 ? 80 + Math.random() * 180 : 4 + Math.random() * 66
    bids.push([price - d, bid])
    asks.push([price + d, ask])
  }
  return { bids, asks }
}

export default function App() {
  const { attachHybridRef, push, pushOrderbook } = useLiveline()

  // A short backfill so the chart opens populated.
  const seed = useMemo<LivelinePoint[]>(() => {
    const now = Date.now() / 1000
    let p = 62
    return Array.from({ length: 80 }, (_, i) => {
      p += (62 - p) * 0.01 + (Math.random() - 0.5) * 1.4
      return { time: now - 45 + (i / 79) * 45, value: p }
    })
  }, [])

  // Live feed: push the price line + the order book each tick.
  useEffect(() => {
    let price = seed[seed.length - 1]!.value
    const timer = setInterval(() => {
      price += (62 - price) * 0.008 + (Math.random() - 0.5) * 1.6
      push({ time: Date.now() / 1000, value: price })
      pushOrderbook(makeBook(price))
    }, 100)
    return () => clearInterval(timer)
  }, [seed, push, pushOrderbook])

  return (
    <SafeAreaView style={styles.root}>
      <Text style={styles.title}>Liveline · Orderbook</Text>
      <Liveline
        style={styles.card}
        data={seed}
        window={45}
        theme='dark'
        valuePrefix='$'
        valueDecimals={0}
        hybridRef={attachHybridRef()}
      />
      <Text style={styles.caption}>
        Bid/ask sizes stream up behind the price line, fed imperatively via pushOrderbook.
      </Text>
    </SafeAreaView>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#0a0a0a', padding: 20, gap: 12 },
  title: { fontSize: 28, fontWeight: '700', color: '#fff' },
  card: { height: 360 },
  caption: { fontSize: 13, color: '#888' },
})
