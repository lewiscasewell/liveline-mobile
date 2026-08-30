# liveline-mobile

An open-source, real-time **line and candlestick** chart, implemented natively
on **iOS** (Swift, `LivelineKit`) and **Android** (Kotlin), with a thin React
Native binding on top via [Nitro Modules](https://nitro.margelo.com). One API
across all three.

It's a deliberate port of the API shape of
[**liveline**](https://github.com/benjitaylor/liveline) by Benji Taylor (MIT,
web/React/canvas) — the prop vocabulary matches so you're not relearning names
across platforms — then **extended with the things that only make sense on a
phone** (see [Built for mobile](#built-for-mobile)).

**Two modes only: line and candle.** This is not a general charting framework —
no generic axes, no arbitrary chart types, no plugin system. If a feature would
make you configure a scale or an axis by hand, it doesn't belong here.

Everything (the render loop, all text/number formatting, the interval bar, the
orderbook stream) is **native** — the JS side just declares props and pushes
ticks, so a fast feed never re-renders React.

---

## Preview

<!-- TODO: add demo videos. On GitHub, drag an .mp4 into the README editor (or any
     issue/PR comment) to upload it and get a https://github.com/user-attachments/…
     URL, then paste that URL on its own line to replace each placeholder below. -->

> **Demo videos coming soon.**

| | |
| --- | --- |
| **Line + momentum** — _video coming soon_ | **Candlesticks** — _video coming soon_ |
| **Multi-series** — _video coming soon_ | **Orderbook stream** — _video coming soon_ |

_See the original web charts in motion in Benji Taylor's
[liveline](https://github.com/benjitaylor/liveline) and its
[write-up](https://benji.org/liveline)._

---

## Built for mobile

liveline-mobile ports [liveline](https://github.com/benjitaylor/liveline)'s API
and modes — line, candle, multi-series, orderbook, momentum, degen, the interval
bar, crosshair scrubbing — faithfully, then adds what only makes sense once a
chart lives on a phone:

- **A native render loop, decoupled from JS.** The line is drawn on the platform's
  own display link (`CADisplayLink` on iOS, `Choreographer` on Android) at the
  screen's refresh rate — **120 Hz on ProMotion**. A fast feed pushes ticks
  straight to native, so React never re-renders per tick.
- **Touch, not hover.** Crosshair scrubbing is **press-and-hold**: hold to inspect
  a point (the line to the right dims), release to resume — the touch-native
  equivalent of the web's mouse hover.
- **Haptics.** Optional `haptics` fire on degen bursts (iOS + Android).
- **Native controls & formatting.** The interval bar is a real native segmented
  control (Liquid Glass on iOS); all number/time formatting and localization
  (`currency`, `locale`, custom fonts) run natively, per frame.
- **An imperative streaming API.** `value` drives the live feed declaratively, or
  `useLiveline().push()` streams through a Nitro `hybridRef` — bypassing React
  entirely for high-frequency feeds.

---

## Using it in React Native

```bash
# npm · yarn · pnpm · bun
npm install liveline-mobile react-native-nitro-modules
```

**Expo:** needs a development build, not Expo Go (`npx expo run:ios` / `run:android`
does the prebuild + linking for you — no config plugin). **Bare RN:** `cd ios && pod install`.

```tsx
import { Liveline, useLiveline } from 'liveline-mobile'
```

**→ The full React Native guide and prop/method reference lives in the package
README: [`packages/liveline-mobile/README.md`](packages/liveline-mobile/README.md)**
(install, quick start, live data, multi-series, orderbook, candles, custom fonts,
formatting/localization, and every prop).

## Using it in Swift (no React Native)

`LivelineKit` is a plain Swift Package (Swift 5.9+, iOS 16+), installable
straight from GitHub:

```swift
.package(url: "https://github.com/lewiscasewell/liveline-mobile", branch: "main")
// then: import LivelineKit
```

The SwiftUI view's modifier names match the RN props:

```swift
import LivelineKit

Liveline(data: data, value: value)
    .color(Color(red: 0.67, green: 0.62, blue: 0.95))
    .theme(.dark)
    .surfaceColor(nil)                 // nil = transparent
    .momentum(.auto)
    .degen()
    .badgeVariant(.accent)
    .showValue()
    .fontFamily("Inter")
    .locale(Locale(identifier: "de-DE"))
    .formatValue { String(format: "$%.2f", $0) }   // full control
    .windows([Window(label: "1m", secs: 60)])
    .frame(height: 300)

// Multi-series and the orderbook overlay:
Liveline()
    .series([ /* LivelineView.SeriesInput per line */ ])
Liveline(data: data, value: value)
    .orderbook(OrderbookData(bids: bids, asks: asks))
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
closures (or `.locale()`) for localization on the Swift side — the `currency` /
`locale` string props are the RN equivalents.

## Using it in Android (Kotlin, no React Native)

The engine ships to Maven Central (namespace `io.github.lewiscasewell`) — add the
single `liveline` artifact (engine + renderer in one AAR), Android 7+ / minSdk 24:

```kotlin
// build.gradle.kts
implementation("io.github.lewiscasewell:liveline:0.1.0")
```

`com.liveline.LivelineView` is a plain Android `View` whose property names match
the RN props. Configure it and drive the live feed with `push` — this is the same
view the RN binding holds:

```kotlin
import com.liveline.LivelineView
import com.liveline.core.LivelinePoint
import com.liveline.core.LivelineTheme
import com.liveline.core.Momentum
import com.liveline.core.BadgeVariant

val chart = LivelineView(context).apply {
    color = Color.parseColor("#AB9EF3")
    theme = LivelineTheme.DARK
    surfaceColor = null                 // null = transparent
    momentum = Momentum.AUTO
    degen = true
    badgeVariant = BadgeVariant.ACCENT
    showValue = true
    numberTypeface = Typeface.create("Inter", Typeface.NORMAL)
    formatValue = { v -> "$%.2f".format(v) }   // full control
}

chart.setData(backfill)                 // backfill only
chart.push(LivelinePoint(time = t, value = v))  // each push appends to the live feed
```

Multi-series and the orderbook overlay:

```kotlin
chart.setSeries(listOf(
    LivelineView.SeriesInput(id = "yes", color = Color.GREEN, label = "Yes", data = yes),
    // one SeriesInput per line…
))
chart.orderbook = OrderbookData(bids = bids, asks = asks)
chart.mode = LivelineMode.CANDLE        // or set candles via setCandles(...)
```

As on iOS, `setData` is **backfill only**; drive the live feed with `push` (each
new point is appended). Number/time formatting is per-frame, so use the
`formatValue` closure and `numberTypeface` for localization on the Kotlin side —
these are the native equivalents of the RN `currency` / `locale` / `fontFamily`
props.

---

## Repository layout

| Path | What |
| --- | --- |
| `ios/Sources/LivelineKit` | The native iOS engine — Swift Package (pure-maths modules + UIKit `LivelineView` + SwiftUI `Liveline`). |
| `android/liveline` | The native Android engine + renderer — the pure-maths modules ported 1-for-1 to Kotlin (`com.liveline.core`, JUnit tests mirror the Swift XCTests) plus the `LivelineView` Canvas renderer (`Choreographer` loop). Published as one AAR. |
| `packages/liveline-mobile` | The React Native library (Nitro binding + JS wrapper). Its README is the RN documentation. |
| `examples/ios/LivelineDemo` | The native Swift showcase — a card per feature (parity with the web liveline examples). |
| `android/demo` | The native Kotlin showcase — the same menu of demos as the iOS one. |
| `examples/rn` | The React Native example app (Expo) — a dropdown showcase of every demo. |

## Development

```bash
swift build          # builds the pure-maths modules on the host (repo root)
swift test           # runs the maths XCTest suite (no simulator)
```

Android (the engine is a 1-for-1 Kotlin port with a mirrored test suite):

```bash
cd android
./gradlew :liveline:testDebugUnitTest   # the maths port's JUnit suite
./gradlew :demo:assembleDebug      # the native Kotlin showcase app
```

The pure-maths modules import only `Foundation`/`CoreGraphics`, so they build and
test on macOS without a simulator; all UIKit view code is guarded with
`#if canImport(UIKit)`. The render loop is a `CADisplayLink`; the ring buffer is
preallocated and fixed-capacity.

**React Native example** (`examples/rn`): needs
[watchman](https://facebook.github.io/watchman/) (`brew install watchman`), then
`npx expo run:ios` or `npx expo run:android` (a dev build — the prebuild + native
linking are automatic). Adding a new native iOS source file to `LivelineKit`
requires a `pod install` in `examples/rn/ios`; changing the Nitro spec
(`src/Liveline.nitro.ts`) requires a nitrogen regen.

- **Format:** `swift format --configuration .swift-format --in-place --recursive ios/Sources`
- **Lint:** `swift format lint --configuration .swift-format --recursive ios/Sources`

## Credit

The API shape (prop names, modes, momentum semantics) is ported from
[**liveline**](https://github.com/benjitaylor/liveline) by Benji Taylor, MIT —
the original web/React/canvas library this is based on. See also his
[write-up](https://benji.org/liveline).



## Licence

MIT.
