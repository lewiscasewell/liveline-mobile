# liveline-mobile

An open-source, real-time **line and candlestick** chart, implemented natively
on iOS (Swift, `LivelineKit`) with a thin React Native binding on top via
[Nitro Modules](https://nitro.margelo.com). Kotlin/Android is planned.

It's a deliberate port of the API shape of
[**liveline**](https://github.com/benjitaylor/liveline) by Benji Taylor (MIT,
web/React/canvas) — the prop vocabulary matches so you're not relearning names
across platforms.

**Two modes only: line and candle.** This is not a general charting framework —
no generic axes, no arbitrary chart types, no plugin system. If a feature would
make you configure a scale or an axis by hand, it doesn't belong here.

Everything (the render loop, all text/number formatting, the interval bar) is
**native** — the JS side just declares props and pushes ticks.

---

## Contents

- [Install](#install) · [Quick start](#quick-start)
- [Live data: `push()` and `useLiveline`](#live-data-push-and-useliveline)
- [Appearance](#appearance): [color & theme](#color--theme) · [transparent surface](#transparent-surface) · [custom fonts](#custom-fonts)
- [Number & time formatting](#number--time-formatting): [`currency` vs `valuePrefix`](#currency-vs-valueprefix) · [localization](#localization)
- [The value overlay & badge](#the-value-overlay--badge)
- [Momentum, degen mode & haptics](#momentum-degen-mode--haptics)
- [The interval bar & candles](#the-interval-bar--candles)
- [Everything else](#everything-else) · [Full prop reference](#full-prop-reference)
- [Swift (SwiftUI / UIKit)](#swift-swiftui--uikit) · [Development](#development)

---

## Install

### React Native

```bash
npm install liveline-mobile react-native-nitro-modules
cd ios && pod install
```

`react-native-nitro-modules` is a peer dependency (the native runtime). New
Architecture (Fabric) is required. Then:

```tsx
import { Liveline, useLiveline } from 'liveline-mobile'
```

### Swift (no React Native)

`LivelineKit` is a plain Swift Package (Swift 5.9+, iOS 16+), installable
straight from GitHub:

```swift
.package(url: "https://github.com/lewiscasewell/liveline-mobile", branch: "main")
// then: import LivelineKit
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
badge, axis, crosshair/OHLC readout and the interval bar.

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
  and a stronger hit on each degen burst. (Physical device / simulator haptics.)

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

## Full prop reference

**Data & mode:** `data` · `value` · `mode` · `candles` · `candleWidth` ·
`liveCandle` · `onModeChange`
**Appearance:** `color` · `theme` · `surfaceColor` · `fontFamily` · `lineWidth`
**Formatting:** `valuePrefix` · `valueSuffix` · `valueDecimals` · `currency` ·
`locale` · `useGrouping`
**Overlay & badge:** `showValue` · `valueMomentumColor` · `badge` · `badgeTail` ·
`badgeVariant`
**Momentum / effects:** `momentum` · `degen` · `haptics` · `pulse`
**Interval bar:** `windows` · `window` · `windowStyle` · `onWindowChange`
**Behaviour:** `grid` · `fill` · `scrub` · `exaggerate` · `paused` · `loading` ·
`emptyText` · `referenceLine` · `lerpSpeed`
**Imperative:** `hybridRef` (from `useLiveline().attachHybridRef()`), `.push(point)`

---

## Swift (SwiftUI / UIKit)

The same feature set, native. SwiftUI modifier names match the props:

```swift
import LivelineKit

Liveline(data: data, value: value)
    .color(Color(red: 0.67, green: 0.62, blue: 0.95))
    .theme(.dark)
    .surfaceColor(nil)                 // nil = transparent
    .momentum(.auto)
    .degen()
    .haptics()
    .badgeVariant(.accent)
    .showValue()
    .fontFamily("Inter")
    .locale(Locale(identifier: "de-DE"))
    .formatValue { String(format: "$%.2f", $0) }   // full control
    .windows([Window(label: "1m", secs: 60)])
    .frame(height: 300)
```

`data` is **backfill only**; drive `value` for the live feed (each new value is
appended). The underlying UIKit view is `LivelineView`, driven imperatively —
this is what the RN binding holds:

```swift
let chart = LivelineView()
chart.color = .systemBlue
chart.push(LivelinePoint(time: t, value: v))
```

Because number/time formatting is per-frame, use `formatValue` / `formatTime`
closures (or `.locale()`) for localization on the Swift side — the `currency`/
`locale` string props are the RN equivalents.

---

## Development

```bash
swift build          # builds the pure-maths modules on the host (repo root)
swift test           # runs the maths XCTest suite (no simulator)
```

The pure-maths modules import only `Foundation`/`CoreGraphics`, so they build and
test on macOS without a simulator; all UIKit view code is guarded with
`#if canImport(UIKit)`. The render loop is a `CADisplayLink`; the ring buffer is
preallocated and fixed-capacity.

**React Native example** (`examples/rn`): needs
[watchman](https://facebook.github.io/watchman/) (`brew install watchman`), then
`npx expo start` + build the iOS app. Adding a new native source file to
`LivelineKit` requires a `pod install` in `examples/rn/ios`.

- **Format:** `swift format --configuration .swift-format --in-place --recursive ios/Sources`
- **Lint:** `swift format lint --configuration .swift-format --recursive ios/Sources`

## Credit

The API shape (prop names, modes, momentum semantics) is ported from
[liveline](https://github.com/benjitaylor/liveline) by Benji Taylor, MIT.

## Licence

MIT.
