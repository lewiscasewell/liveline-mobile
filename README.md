# liveline-mobile

An open-source, real-time **line and candlestick** chart, implemented natively
on iOS (Swift, `LivelineKit`) with a thin React Native binding on top via
[Nitro Modules](https://nitro.margelo.com). Kotlin/Android is coming next, with
the same API.

It's a deliberate port of the API shape of
[**liveline**](https://github.com/benjitaylor/liveline) by Benji Taylor (MIT,
web/React/canvas) — the prop vocabulary matches so you're not relearning names
across platforms.

**Two modes only: line and candle.** This is not a general charting framework —
no generic axes, no arbitrary chart types, no plugin system. If a feature would
make you configure a scale or an axis by hand, it doesn't belong here.

Everything (the render loop, all text/number formatting, the interval bar, the
orderbook stream) is **native** — the JS side just declares props and pushes
ticks, so a fast feed never re-renders React.

---

## Using it in React Native

```bash
npm install liveline-mobile react-native-nitro-modules
cd ios && pod install
```

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

---

## Repository layout

| Path | What |
| --- | --- |
| `ios/Sources/LivelineKit` | The native engine — Swift Package (pure-maths modules + UIKit `LivelineView` + SwiftUI `Liveline`). |
| `packages/liveline-mobile` | The React Native library (Nitro binding + JS wrapper). Its README is the RN documentation. |
| `examples/ios/LivelineDemo` | The native Swift showcase — a card per feature (parity with the web liveline examples). |
| `examples/rn` | The React Native example app (Expo). |

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
`LivelineKit` requires a `pod install` in `examples/rn/ios`; changing the Nitro
spec (`src/Liveline.nitro.ts`) requires a nitrogen regen.

- **Format:** `swift format --configuration .swift-format --in-place --recursive ios/Sources`
- **Lint:** `swift format lint --configuration .swift-format --recursive ios/Sources`

## Credit

The API shape (prop names, modes, momentum semantics) is ported from
[liveline](https://github.com/benjitaylor/liveline) by Benji Taylor, MIT.

## Licence

MIT.
