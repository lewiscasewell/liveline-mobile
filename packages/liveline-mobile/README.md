# liveline-mobile

Real-time **line and candlestick** charts for React Native — a live price line
that scrolls at the display's refresh rate, with multi-series, an orderbook
stream, candles, momentum, a native interval bar, and native number/time
formatting.

The render loop, all text/number formatting and the interval bar are **native**
(Swift on iOS, Kotlin on Android); the JS side just declares props and pushes
ticks, so a fast feed never re-renders React. It's a port of the API shape of
[**liveline**](https://github.com/benjitaylor/liveline) by Benji Taylor (MIT,
web/React/canvas) — the prop vocabulary matches, so names carry across platforms
— then extended with mobile-native touches (see
[Built for mobile](#built-for-mobile)).

> **Two modes only: line and candle.** Not a general charting framework — no
> generic axes, no arbitrary chart types, no plugin system.

---

## Preview

<!-- TODO: add demo videos. On GitHub, drag an .mp4 into the README editor (or any
     issue/PR comment) to upload it and get a https://github.com/user-attachments/…
     URL, then paste that URL on its own line in place of a placeholder below. -->

> **Demo videos coming soon.**

| | |
| --- | --- |
| **Line + momentum** — _video coming soon_ | **Candlesticks** — _video coming soon_ |
| **Multi-series** — _video coming soon_ | **Orderbook stream** — _video coming soon_ |

---

## Built for mobile

liveline-mobile ports [liveline](https://github.com/benjitaylor/liveline)'s API
and modes — line, candle, multi-series, orderbook, momentum, degen, the interval
bar, crosshair scrubbing — faithfully, then adds what only makes sense once a
chart lives on a phone:

- **A native render loop, decoupled from JS** — drawn on the platform display
  link (`CADisplayLink` / `Choreographer`) at the screen's refresh rate, **120 Hz
  on ProMotion**. `push()` a tick and React never re-renders.
- **Touch, not hover** — crosshair scrubbing is **press-and-hold**: hold to
  inspect (the line to the right dims), release to resume.
- **Haptics** — optional, firing on degen bursts (iOS + Android).
- **Native controls & formatting** — the interval bar is a real native segmented
  control (Liquid Glass on iOS); number/time formatting, `currency`/`locale`
  localization and custom fonts all run natively, per frame.
- **An imperative streaming API** — `value` drives the feed declaratively, or
  `useLiveline().push()` streams through a Nitro `hybridRef`, bypassing React for
  high-frequency feeds.

---

## Contents

- [Preview](#preview) · [Built for mobile](#built-for-mobile)
- [Install](#install) · [Quick start](#quick-start)
- [Live data: `push()` and `useLiveline`](#live-data-push-and-useliveline)
- [Multi-series](#multi-series) · [Orderbook stream](#orderbook-stream)
- [Appearance](#appearance): [color & theme](#color--theme) · [transparent surface](#transparent-surface) · [custom fonts](#custom-fonts)
- [Number & time formatting](#number--time-formatting): [`currency` vs `valuePrefix`](#currency-vs-valueprefix) · [localization](#localization)
- [The value overlay & badge](#the-value-overlay--badge)
- [Momentum, degen mode & haptics](#momentum-degen-mode--haptics)
- [The interval bar & candles](#the-interval-bar--candles)
- [Everything else](#everything-else) · [Full prop & method reference](#full-prop--method-reference)
- [Platforms](#platforms) · [Swift](#also-available-as-a-swift-package)

---

## Install

```bash
npm install liveline-mobile react-native-nitro-modules
cd ios && pod install
```

`react-native-nitro-modules` is a peer dependency (the native runtime). The **New
Architecture (Fabric) is required**. Works in bare React Native and in Expo
(dev/prod builds — it ships native code, so it isn't in Expo Go). Then:

```tsx
import { Liveline, useLiveline } from 'liveline-mobile'
```

---

## Quick start

```tsx
import { useEffect } from 'react'
import { Liveline, useLiveline } from 'liveline-mobile'

export function Chart({ history }: { history: { time: number; value: number }[] }) {
  const { attachHybridRef, push } = useLiveline()

  // Feed live ticks — one call per tick, never per frame. React never re-renders.
  useEffect(() => {
    const id = setInterval(() => push({ time: Date.now() / 1000, value: nextPrice() }), 1000)
    return () => clearInterval(id)
  }, [push])

  return (
    <Liveline
      style={{ height: 320 }}
      data={history}          // initial backfill (see below)
      color="#AB9FF2"
      theme="light"
      badge
      showValue
      valuePrefix="$"
      hybridRef={attachHybridRef()}
    />
  )
}
```

Two things drive a chart:

- **`data`** — the initial history (backfill). It's the *starting* series, not a
  per-frame feed. Send it once (and again when you change timeframe); don't push
  a growing array every tick.
- **`push({ time, value })`** — the live feed. The native ring buffer owns the
  data; the render loop interpolates and scrolls at the display refresh rate.

---

## Feature reference

Every prop, one at a time — what it does, a minimal snippet, and a demo clip. The
props mirror the original web [liveline](https://github.com/benjitaylor/liveline);
where mobile changes the behaviour it's called out (➕ = mobile-only addition).

<!-- This gallery is being built out feature by feature; the older topical
     how-tos below are folded in and trimmed as each group lands. -->

### Live data

#### `data` — backfill history

The initial series drawn when the chart mounts — a one-off backfill so the chart
opens populated, not from empty. It is **not** the live path: send it once (and
again when the timeframe changes), never a growing array every tick.

```tsx
<Liveline data={history} />   // history: { time: number; value: number }[]
```
<!-- 🎥 record: a chart mounting already populated from `data` -->
> _Video coming soon._

#### `value` — the live value

The latest value. Each new `value` is appended and smoothly interpolated to, so a
low-frequency source still scrolls at the display's refresh rate. Convenient for
React-driven updates; for a high-frequency feed prefer `push()` (below), which
never re-renders React.

```tsx
<Liveline data={history} value={price} />
```
<!-- 🎥 record: value updating live, badge tracking the tip -->
> _Video coming soon._

#### `push()` / `useLiveline()` — the imperative feed

`useLiveline()` hands you `push()` (and `pushOrderbook()`) wired to the chart via
a Nitro `hybridRef`, so ticks go straight to native — no React re-render per tick.

```tsx
const { push, attachHybridRef } = useLiveline()
useEffect(() => {
  const id = setInterval(() => push({ time: Date.now() / 1000, value: next() }), 100)
  return () => clearInterval(id)
}, [push])

return <Liveline data={history} hybridRef={attachHybridRef()} />
```
<!-- 🎥 record: a fast (50–100Hz) push feed staying smooth -->
> _Video coming soon._

#### `series` — multiple lines

Several equal-peer lines on one chart. A non-empty `series` replaces
`data`/`value`; each line carries its own `id`, `color`, `label` and backfill
`data`, and streams live via `push(point, seriesId)`. A legend toggles lines.

```tsx
<Liveline
  series={[
    { id: 'yes', color: '#3b82f6', label: 'Yes', data: yesHistory },
    { id: 'no',  color: '#ef4444', label: 'No',  data: noHistory },
  ]}
/>
// live: push({ time, value }, 'yes')
```
<!-- 🎥 record: Prediction-market demo, tapping legend chips to toggle lines -->
> _Video coming soon._

#### `onSeriesToggle` — legend toggle callback

Fires when a legend chip shows/hides a line: `(id, visible) => void`.

```tsx
<Liveline series={series} onSeriesToggle={(id, visible) => console.log(id, visible)} />
```
<!-- 🎥 record: tapping a chip, the line hiding, the callback logging -->
> _Video coming soon._

#### `seriesToggleCompact` — dots-only legend

Shows the legend as colour dots without labels. Default `false`.

```tsx
<Liveline series={series} seriesToggleCompact />
```
<!-- 🎥 record: the legend as labels vs compact dots -->
> _Video coming soon._

### Appearance

#### `color` — accent

The accent colour the whole palette derives from (line, dot, badge, fill).
Default `#3b82f6`.

```tsx
<Liveline data={data} color='#8b5cf6' />
```
<!-- 🎥 record: same chart in two accent colours -->
> _Video coming soon._

#### `theme` — light / dark

Base surface tone for background, grid and text. `'light' | 'dark'`, default
`'dark'`. The chart is otherwise transparent, so it sits on whatever is behind it.

```tsx
<Liveline data={data} theme='light' />
```
<!-- 🎥 record: toggling theme light ↔ dark -->
> _Video coming soon._

#### `surfaceColor` ➕ — opaque card

Mobile addition. By default the chart is **transparent**, so it sits on whatever
is behind it. Set `surfaceColor` to paint an opaque card background instead —
independent of `theme`.

```tsx
<Liveline data={data} surfaceColor='#1c1530' />
```
<!-- 🎥 record: transparent chart over a gradient, then an opaque surfaceColor -->
> _Video coming soon._

#### `grid` — Y-axis grid & labels

Toggles the horizontal grid lines and their value labels. The time axis is
unaffected. Default `true`.

```tsx
<Liveline data={data} grid={false} />
```
<!-- 🎥 record: Basic chart, grid on → off -->
> _Video coming soon._

#### `fill` — area under the line

The gradient fill beneath the curve. Default `true`; set `false` for a bare line.

```tsx
<Liveline data={data} fill={false} />
```
<!-- 🎥 record: same chart with fill on → off -->
> _Video coming soon._

#### `padding` — chart insets

Override the plot insets (points): `{ top?, right?, bottom?, left? }`. Any side
you omit keeps its default. Handy to make room for your own chrome, or to tighten
the chart.

```tsx
<Liveline data={data} padding={{ top: 24, right: 12 }} />
```
<!-- 🎥 record: default insets vs a custom padding -->
> _Video coming soon._

#### `lineWidth` — stroke width

The line's stroke width in points. Default `2`.

```tsx
<Liveline data={data} lineWidth={4} />
```
<!-- 🎥 record: same chart at lineWidth 2 → 5 -->
> _Video coming soon._

#### `badge` — the value pill

The rounded pill that tracks the chart tip and shows the current value. Default
`true`; set `false` to hide it.

```tsx
<Liveline data={data} value={value} badge={false} />
```
<!-- 🎥 record: chart with badge on → off -->
> _Video coming soon._

#### `badgeVariant` — pill style

`'default' | 'minimal' | 'accent'` (default `'default'`). `minimal` drops the
tail and uses the surface tone; `accent` fills the pill with the accent colour.

```tsx
<Liveline data={data} value={value} badgeVariant='accent' />
```
<!-- 🎥 record: the three badge variants side by side -->
> _Video coming soon._

#### `badgeTail` — the pill's pointer

The pointed tail joining the pill to the live dot. Default `true`; `false` gives
a plain rounded pill (also implied by the `minimal` variant).

```tsx
<Liveline data={data} value={value} badgeTail={false} />
```
<!-- 🎥 record: badge with tail on → off -->
> _Video coming soon._

#### `pulse` — the live-dot ring

The pulsing ring radiating from the live dot. Default `true`.

```tsx
<Liveline data={data} value={value} pulse={false} />
```
<!-- 🎥 record: the dot with the pulse ring on → off -->
> _Video coming soon._

### Behaviour

#### `lerpSpeed` — interpolation speed

How quickly the line eases toward each new value, `0–1`. Default `0.08`. Lower is
smoother/laggier; higher snaps faster.

```tsx
<Liveline data={data} value={value} lerpSpeed={0.2} />
```
<!-- 🎥 record: a jumpy feed at low vs high lerpSpeed -->
> _Video coming soon._

#### `emptyText` — empty state

The text shown, centred, when there's no data yet (and not `loading`). Default
`'No data to display'`.

```tsx
<Liveline data={[]} emptyText='Waiting for feed…' />
```
<!-- 🎥 record: an empty chart showing the empty text, then data arriving -->
> _Video coming soon._

#### `haptics` ➕ — tactile feedback

Mobile addition. Fires a short haptic on degen bursts (strong up-moves). Default
`false`. Pairs with `degen`.

```tsx
<Liveline data={data} value={value} degen haptics />
```
<!-- 🎥 record: (device only) a degen burst with a haptic tick -->
> _Video coming soon._

### Number & time formatting

Formatting is **native** and runs per frame — no JS on the render path. Instead of
the web's `formatValue`/`formatTime` closures, mobile takes declarative props and
builds the platform formatter (`NumberFormatter` on iOS, `NumberFormat` on
Android). They drive the badge, the value overlay, the crosshair, and the Y-axis
labels alike.

#### `valuePrefix` / `valueSuffix` / `valueDecimals`

The simple path: a leading string, a trailing string, and the fraction-digit
count (default `2`). Grouping separators are applied for the locale.

```tsx
<Liveline data={data} value={value} valuePrefix='$' valueDecimals={0} />
<Liveline data={data} value={hr} valueSuffix=' bpm' valueDecimals={0} />
```
<!-- 🎥 record: the same feed as "$1,234", "1234.00 bpm", "12%" -->
> _Video coming soon._

#### `currency` — currency style

An ISO 4217 code (e.g. `'USD'`, `'EUR'`, `'JPY'`). Switches to the locale's
currency style — symbol, placement and the currency's own fraction digits (0 for
JPY, 2 for USD). `valuePrefix`/`valueSuffix`/`valueDecimals` don't apply here.

```tsx
<Liveline data={data} value={value} currency='USD' />   // $9,680.78
```
<!-- 🎥 record: the same value as USD, EUR, JPY -->
> _Video coming soon._

#### `locale` — formatting locale

A BCP-47 tag (e.g. `'de-DE'`) controlling grouping/decimal separators and the
currency symbol's placement. Defaults to the device locale.

```tsx
<Liveline data={data} value={value} currency='EUR' locale='de-DE' />  // 9.680,78 €
```
<!-- 🎥 record: one value under en-US vs de-DE -->
> _Video coming soon._

#### `useGrouping` — thousands separators

Whether to group the integer part (`1,234,567`). Default `true`.

```tsx
<Liveline data={data} value={value} useGrouping={false} />
```
<!-- 🎥 record: a large value with grouping on → off -->
> _Video coming soon._

#### `fontFamily` — custom font

Renders numbers and labels in a custom font (a bundled font on Expo/RN, resolved
natively). Falls back to the tabular monospace default.

```tsx
<Liveline data={data} value={value} fontFamily='Inter' />
```
<!-- 🎥 record: default font vs a bundled custom font -->
> _Video coming soon._

### Momentum & effects

#### `momentum` — direction cues

Directional chevrons on the live dot and a green-up / red-down tint on the badge.
`'off' | 'auto' | 'up' | 'down' | 'flat'` (default `'auto'`, which detects
direction from the recent slope; the explicit values force it).

```tsx
<Liveline data={data} value={value} momentum='auto' />
```
<!-- 🎥 record: a rising then falling feed, badge tinting green → red -->
> _Video coming soon._

#### `scrub` — press-and-hold crosshair

Touch and hold to inspect a point: a crosshair snaps to the line, the value +
time show, and the line to the right of your finger dims. Release to resume.
Default `true`.

```tsx
<Liveline data={data} value={value} scrub />
```
<!-- 🎥 record: pressing and dragging along the line, crosshair + values -->
> _Video coming soon._

#### `tooltipY` / `tooltipOutline` — crosshair tooltip

Tune the scrub tooltip: `tooltipY` is the tooltip text's vertical offset in points
(default `14`); `tooltipOutline` strokes an outline behind the text for legibility
over the line (default `true`).

```tsx
<Liveline data={data} value={value} tooltipY={20} tooltipOutline={false} />
```
<!-- 🎥 record: scrubbing, tooltip offset + outline on vs off -->
> _Video coming soon._

#### `exaggerate` — amplify small moves

Tightens the Y-axis around the recent range so tiny fluctuations fill the height
(e.g. a heart-rate or temperature line). Default `false`.

```tsx
<Liveline data={data} value={bpm} exaggerate valueSuffix=' bpm' />
```
<!-- 🎥 record: a near-flat feed, normal vs exaggerated -->
> _Video coming soon._

#### `showValue` / `valueMomentumColor` — the big number

`showValue` draws the current value large, over the chart. `valueMomentumColor`
tints that number green/red by momentum. Both default `false`.

```tsx
<Liveline data={data} value={value} showValue valueMomentumColor currency='USD' />
```
<!-- 🎥 record: the large value updating and tinting with direction -->
> _Video coming soon._

#### `degen` — burst + shake

Confetti-style particle bursts and a screen shake on strong up-moves. Pairs with
`momentum` and `haptics`. Default `false`.

```tsx
<Liveline data={data} value={value} degen momentum='auto' badgeVariant='accent' haptics />
```
<!-- 🎥 record: a pump triggering the sparks + shake -->
> _Video coming soon._

### Candles

#### `mode` — line or candle

`'line' | 'candle'` (default `'line'`). In candle mode the chart draws OHLC
candlesticks instead of the line.

```tsx
<Liveline mode='candle' candles={candles} liveCandle={live} candleWidth={3} />
```
<!-- 🎥 record: toggling a chart between line and candle -->
> _Video coming soon._

#### `candles` / `candleWidth` / `liveCandle`

`candles` is the OHLC history (`{ time, open, high, low, close }[]`); `candleWidth`
is the seconds each candle spans; `liveCandle` is the currently-forming candle,
updated every tick so its wicks grow in place until the bucket rolls over.

```tsx
<Liveline mode='candle' candles={history} candleWidth={3} liveCandle={live} />
```
<!-- 🎥 record: the live candle growing, then a new bucket starting -->
> _Video coming soon._

#### candle ↔ line morph

Flipping `mode` between `'candle'` and `'line'` **animates** the transition — the
candles collapse toward their closes while the line draws in (from `data`/`value`).
So provide `data` (the tick line) alongside `candles` if you want the morph, and
just toggle `mode`. There's no separate "line mode" prop — see
[divergences](../../PARITY.md#deliberate-divergences).

```tsx
<Liveline mode={showCandles ? 'candle' : 'line'} data={ticks} candles={history} liveCandle={live} candleWidth={3} />
```
<!-- 🎥 record: toggling mode, candles melting into the line and back -->
> _Video coming soon._

### The interval bar

#### `window` — visible span

The visible time window, in seconds (default `30`). Changing it smoothly zooms.

```tsx
<Liveline data={data} window={60} />
```
<!-- 🎥 record: window changing 30s → 5m, the line zooming -->
> _Video coming soon._

#### `windows` / `windowStyle` / `onWindowChange` — the native bar

Passing `windows` renders a **native** interval bar (e.g. 30s / 1m / 5m) below the
chart; tapping a chip smoothly zooms and fires `onWindowChange(secs)`.
`windowStyle` (`'default' | 'rounded' | 'text'`) styles it (iOS; the Android bar
has a single pill style for now).

```tsx
<Liveline
  data={data}
  windows={[{ label: '30s', secs: 30 }, { label: '1m', secs: 60 }, { label: '5m', secs: 300 }]}
  windowStyle='rounded'
  onWindowChange={(secs) => console.log(secs)}
/>
```
<!-- 🎥 record: tapping the 30s / 1m / 5m chips -->
> _Video coming soon._

### States

#### `loading` — connecting

A breathing placeholder line while data is loading; when it clears, the chart
morphs into the (backfilled) data. Default `false`.

```tsx
<Liveline data={history} loading={isConnecting} />
```
<!-- 🎥 record: loading breathing line → morph into data -->
> _Video coming soon._

#### `paused` — freeze scrolling

Freezes the chart's scroll while data keeps arriving underneath; on resume it
catches up. Default `false`.

```tsx
<Liveline data={data} value={value} paused={isPaused} />
```
<!-- 🎥 record: pausing, data building up, then resuming/catch-up -->
> _Video coming soon._

### Overlays

#### `referenceLine` — a fixed marker

A horizontal line at a fixed value with an optional label, always kept in view by
the autoscale. `{ value, label? }`.

```tsx
<Liveline data={data} value={value} referenceLine={{ value: 67500, label: 'Above $67,500' }} />
```
<!-- 🎥 record: the reference line held in view as the line moves around it -->
> _Video coming soon._

#### `orderbook` — depth stream

Bid/ask depth (`{ bids, asks }`, each `[price, size][]`). Resting sizes float up
behind the price line — green bids, red asks — faster when the price is moving.
Stream it live via `useLiveline().pushOrderbook()`.

```tsx
const { pushOrderbook } = useLiveline()
// each tick: pushOrderbook({ bids: [[price - d, size], …], asks: [[price + d, size], …] })
```
<!-- 🎥 record: the bid/ask sizes streaming up behind the price line -->
> _Video coming soon._

---

## Live data: `push()` and `useLiveline`

`useLiveline()` owns the imperative handle so you never touch `hybridRef`
plumbing:

```tsx
const { attachHybridRef, push } = useLiveline()
// …
<Liveline data={history} hybridRef={attachHybridRef()} />
push({ time, value })   // safe no-op until the chart mounts
```

To call `push()` from a component *other* than the one rendering `<Liveline>`,
wrap a subtree in `<LivelineProvider>` — a `<Liveline>` inside it auto-registers
its handle, and `useLiveline().push()` anywhere in the subtree targets it (no
`hybridRef` wiring at all):

```tsx
<LivelineProvider>
  <Liveline data={history} />      {/* auto-registers */}
  <PriceFeed />                    {/* calls useLiveline().push() */}
</LivelineProvider>
```

**`push()` auto-buckets to the window.** It commits one point roughly every
`window / 300` seconds and slides the head between commits — so a fast feed on a
30-minute window paints at that window's resolution, and a live window keeps
every tick. Just call it once per data tick; no per-window bookkeeping.

> Pre-decimate history to roughly the visible resolution (a few hundred points).
> The chart draws ~one point per pixel and the native buffer holds ~8192; a dev
> warning fires above ~4000 points.

---

## Multi-series

Pass **`series`** instead of `data`/`value` to draw several **equal-peer** lines
on one chart. Each series gets its own colour, endpoint dot, faded dashed
baseline and endpoint label; the Y-axis auto-ranges over the visible series.

```tsx
<Liveline
  style={{ height: 320 }}
  series={[
    { id: 'yes',   color: '#3b82f6', label: 'Yes',   data: yesHistory },
    { id: 'no',    color: '#ef4444', label: 'No',    data: noHistory },
    { id: 'maybe', color: '#f59e0b', label: 'Maybe', data: maybeHistory },
  ]}
  valueSuffix="%"
  valueDecimals={0}
  hybridRef={attachHybridRef()}
/>
```

- A **legend of toggle chips** (colour dot + label) appears above the chart — tap
  a chip to hide/show that line; the shared Y-range re-fits to what's visible.
- **Live updates** route by id: `push({ time, value }, seriesId)`.
- **Hover** (press-and-hold) shows a crosshair, a filled dot on each visible line
  at that time, and a top row of per-series values
  (`16:31:48 · Yes 68% · No 7% · Maybe 25%`).
- Multi-series is line-mode only; the single-series badge / value overlay /
  momentum don't apply (the per-series labels stand in).

```tsx
// each outcome pushes once per tick, routed by series id
for (const o of outcomes) push({ time, value: o.value }, o.id)
```

---

## Orderbook stream

Pass an **`orderbook`** snapshot to render a Kalshi-style depth stream behind the
price line. `bids` and `asks` are arrays of **`[price, size]`** tuples; the
resting sizes float up behind the line as a uniform, left-aligned column and fade
out — **green for bids, red for asks, bigger orders brighter**. The stream speed
reacts to price momentum and orderbook churn (how fast the totals change): calm
markets drift, volatile ones rush.

```tsx
const { attachHybridRef, push, pushOrderbook } = useLiveline()

// price line + depth, each tick
push({ time, value: price })
pushOrderbook({
  bids: [[price - 0.1, 1200], [price - 0.2, 800]],
  asks: [[price + 0.1, 950],  [price + 0.2, 1500]],
})

<Liveline data={seed} value={price} valuePrefix="$" hybridRef={attachHybridRef()} />
```

- **`pushOrderbook({ bids, asks })`** — the imperative path (via `useLiveline()`),
  with no React re-render. Prefer it for a high-frequency depth feed.
- **`orderbook` prop** — the declarative equivalent, for React-driven updates:

```tsx
<Liveline data={seed} value={price} orderbook={{ bids, asks }} />
```

Pair it with the price line (`value` / `push()`); the orderbook is an overlay,
not a replacement for the line.

---

## Appearance

### color & theme

```tsx
<Liveline color="#AB9FF2" theme="dark" />
```

- **`color`** — one accent colour; the whole palette (line, fill, badge, dot) is
  derived from it. Momentum green/red are always semantic, independent of accent.
- **`theme`** — `'light' | 'dark'` (default `'dark'`). Sets the *tone* of the
  ink (line, grid, labels, crosshair). **It doesn't paint a background** — see
  below.

### Transparent surface

By default the chart is **transparent** (like web liveline): whatever is behind
the view shows through, and `theme` just sets the ink tone to match it.

```tsx
// Transparent — put it on any background and pick a theme that suits it:
<View style={{ backgroundColor: '#0a0a0a' }}>
  <Liveline data={history} theme="dark" />
</View>

// Or make it a self-contained card with its own opaque fill:
<Liveline data={history} theme="dark" surfaceColor="#1c1530" />
```

- Omit **`surfaceColor`** → transparent (the container supplies the background).
- Set an opaque `surfaceColor` → the chart paints its own background.

### Custom fonts

Set **`fontFamily`** to change the font of *all* chart text — the value overlay,
badge, axis, crosshair/OHLC readout, orderbook labels and the interval bar.

Following the usual RN pattern, **fonts are referenced by name, not bundled by
the library.** Register the family in *your* app, then pass its name:

**Expo:**
```ts
// app.json → expo-font plugin, or at runtime:
import { useFonts } from 'expo-font'
useFonts({ Inter: require('./assets/Inter-Regular.ttf') })
```
**Bare RN:** drop the `.ttf`/`.otf` in your assets and run
`npx react-native-asset`.

```tsx
<Liveline data={history} fontFamily="Inter" />
```

Numeric labels always keep **monospaced digits** (so ticking values don't
jiggle), whatever the family. An unregistered name falls back to the system
font — it never crashes.

---

## Number & time formatting

All numbers are formatted **natively** (per frame, across many labels), so
formatting is declarative — you can't pass a JS formatter callback.

### `currency` vs `valuePrefix`

These are two different jobs — this is the bit people confuse:

| Want | Use | Example |
| --- | --- | --- |
| **Money** | `currency` | `currency="USD"` → `$1,234.56`; `currency="EUR" locale="de-DE"` → `1.234,56 €` |
| **A non-currency unit** | `valuePrefix` / `valueSuffix` | `valueSuffix=" bpm"` → `72 bpm`; `valuePrefix="$"` → `$1234.56` |

- **`currency`** (ISO 4217, type-safe autocomplete) formats values as **localized
  currency** — the symbol, its placement, *and* the currency's default decimals
  (0 for JPY, 2 for USD) all follow the locale. It **ignores** `valuePrefix`/
  `valueSuffix`/`valueDecimals`.
- **`valuePrefix`/`valueSuffix`** are plain affixes for units (`%`, `bpm`, `×`).
  Use `valueDecimals` and `useGrouping` alongside them.

```tsx
<Liveline currency="JPY" />                 // ¥1,235   (0 decimals, localized)
<Liveline valuePrefix="$" valueDecimals={2} />  // $1234.56 (plain)
<Liveline valueSuffix=" bpm" valueDecimals={0} />// 72 bpm
```

### Localization

Formatting is **device-locale by default** (correct decimal/grouping separators,
localized month names & field order, 12/24-hour), and overridable:

- **`locale`** (BCP-47, e.g. `"de-DE"`) overrides the device locale for **both
  numbers and time**. Defaults to the device locale.
- **`useGrouping`** toggles thousands separators (default: on).

```tsx
<Liveline currency="EUR" locale="de-DE" />   // 1.234,56 €, and de-DE time labels
```

> `currency` is a finite ISO 4217 union so typos are caught at compile time;
> `locale` is a plain string because BCP-47 is open-ended.

---

## The value overlay & badge

**Value overlay** — a large live number above the plot, with an Apple-style
per-digit roll animation:

```tsx
<Liveline showValue valueMomentumColor />
```
- **`showValue`** draws it. **`valueMomentumColor`** tints it green up / red down.

**Badge** — the pill at the live dot:

```tsx
<Liveline badge badgeTail badgeVariant="accent" />
```
- **`badgeVariant`**: `'default'` (momentum green/red) · `'minimal'` (neutral
  pill) · `'accent'` (filled with the line colour, arrows still show).
- **`badgeTail`** toggles the pointer toward the dot.

---

## Momentum, degen mode & haptics

```tsx
<Liveline momentum="auto" degen haptics />
```

- **`momentum`**: `'auto'` (detect direction) · `'up'` · `'down'` · `'off'`.
  Draws directional chevrons on the live dot and tints the badge.
- **`degen`**: on a fast upward move the chart **shakes** and **line-coloured
  sparks** burst from the live dot. Great with `momentum`.
- **`haptics`**: a light tap as the crosshair crosses each step while scrubbing,
  and a stronger hit on each degen burst.

---

## The interval bar & candles

**Interval bar** — a built-in, native segmented control (Liquid Glass on iOS 26)
that reports the chosen span. You refetch history on change:

```tsx
const WINDOWS = [
  { label: '1H', secs: 3600 },
  { label: '30M', secs: 1800 },
  { label: 'Live', secs: 30 },
]

<Liveline
  windows={WINDOWS}
  window={interval}                    // current span (seconds)
  windowStyle="rounded"                // 'default' | 'rounded' | 'text'
  onWindowChange={(secs) => refetch(secs)}
/>
```

**Candles** — switch to candle mode; an optional line/candle toggle appears at
the end of the bar:

```tsx
<Liveline
  mode={mode}                          // 'line' | 'candle'
  candles={ohlc}                       // { time, open, high, low, close }[]
  candleWidth={interval / ohlc.length} // seconds per candle
  liveCandle={forming}                 // the currently-forming candle (optional)
  onModeChange={setMode}
/>
```

The live candle streams from the same `push()` feed and grows its wicks; the
line fades out as candles grow in when you switch. Momentum arrows, the badge and
the value overlay all persist in candle mode.

---

## Everything else

| Prop | Meaning |
| --- | --- |
| `grid` | value grid + labels (default `true`) |
| `fill` | area fill under the line (default `true`) |
| `scrub` | press-and-hold crosshair scrubbing (default `true`) |
| `pulse` | pulsing ring on the live dot (default `true`) |
| `exaggerate` | tighten the Y-range so small moves fill the height (default `false`) |
| `paused` | freeze scrolling while data keeps arriving; catches up on resume |
| `loading` | breathing loading line (morphs into data when it arrives) |
| `emptyText` | message shown when `data` is empty |
| `referenceLine` | `{ value, label? }` — a horizontal marker kept in view |
| `lineWidth` | stroke width in points (default `2`) |
| `lerpSpeed` | base easing speed per 60fps frame, `0…1` (default `0.08`) |

## Full prop & method reference

**Data & mode:** `data` · `value` · `series` · `orderbook` · `mode` · `candles` ·
`candleWidth` · `liveCandle` · `onModeChange`
**Appearance:** `color` · `theme` · `surfaceColor` · `fontFamily` · `lineWidth`
**Formatting:** `valuePrefix` · `valueSuffix` · `valueDecimals` · `currency` ·
`locale` · `useGrouping`
**Overlay & badge:** `showValue` · `valueMomentumColor` · `badge` · `badgeTail` ·
`badgeVariant`
**Momentum / effects:** `momentum` · `degen` · `haptics` · `pulse`
**Interval bar:** `windows` · `window` · `windowStyle` · `onWindowChange`
**Behaviour:** `grid` · `fill` · `scrub` · `exaggerate` · `paused` · `loading` ·
`emptyText` · `referenceLine` · `lerpSpeed`
**Imperative** (from `useLiveline()`): `attachHybridRef()` · `push(point, seriesId?)` ·
`pushOrderbook({ bids, asks })`

---

## Platforms

| Platform | Status |
| --- | --- |
| **iOS** | ✅ Shipping (Swift `LivelineKit`, iOS 16+) |
| **Android** | ✅ Supported (Kotlin) — beta; a few props not yet wired (see below) |

The API is identical across platforms — the same JavaScript renders on both. The
Android renderer is a native `Canvas`/`Choreographer` port of the engine, at
full feature parity for the core: line & candle modes, multi-series, the
orderbook stream, momentum, degen, the value overlay, reference lines,
`exaggerate`, loading/paused, press-and-hold scrubbing, and the interval bar
(`windows` / `onWindowChange`).

Not yet wired on Android (they no-op there for now, and are on the roadmap):
`windowStyle` variants (the Android bar has a single pill style), `surfaceColor`,
`haptics`, `fontFamily`, and `currency` / `locale` number formatting (use
`valuePrefix` / `valueSuffix` / `valueDecimals`, which do work). Nothing about
your JavaScript needs to change as these land.

### Also available as a Swift package

The engine, `LivelineKit`, is a plain Swift Package (Swift 5.9+, iOS 16+) with a
SwiftUI `Liveline` view whose modifier names match these props — usable directly,
without React Native. See the [repository](https://github.com/lewiscasewell/liveline-mobile)
for the Swift API and the full example app.

## Credit

The API shape (prop names, modes, momentum semantics) is ported from
[**liveline**](https://github.com/benjitaylor/liveline) by Benji Taylor, MIT —
the original web/React/canvas library this is based on. See also his
[write-up](https://benji.org/liveline).

liveline-mobile adds the mobile-native layer on top (see
[Built for mobile](#built-for-mobile)).

## Licence

MIT.
