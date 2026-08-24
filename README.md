# liveline-mobile

An open-source, real-time line and candlestick chart library, implemented
natively on iOS (Swift) and Android (Kotlin), with a thin React Native binding
on top via Nitro Modules.

It is a deliberate port of the API shape of [**liveline**](https://github.com/)
by Benji Taylor (MIT, web/React/canvas). The prop vocabulary matches the web
library so that users moving between platforms are not relearning names. The
canonical vocabulary and the handful of intentional divergences live in
[`spec/API.md`](spec/API.md).

**Two modes only: line and candle.** This is not a general charting framework —
there is no generic axis primitive, no arbitrary chart types, no plugin system.
If a feature would require a user to configure a scale or an axis by hand, it
does not belong here.

## Status

| Phase | Scope | State |
| ----- | ----- | ----- |
| 1 | iOS (`LivelineKit`), full line-mode parity with web liveline | ✅ done |
| 2 | `spec/fixtures/*.json`, `spec/API.md` | ⬜ next |
| 3 | Android (`liveline`) | ⬜ |
| 4 | React Native binding (Nitro) | ⬜ |
| 5 | Release-ready packaging (no publish) | ⬜ |

## Architecture

The render loop is native and never asks the caller for anything
(`CADisplayLink` on iOS, `Choreographer` on Android). The ring buffer is owned
natively, preallocated, fixed capacity. New data arrives via `push(point)` —
one call per tick, never per frame. Interpolation between ticks, the scrolling
x-offset and the eased y-domain are all computed in the native frame callback.

The maths live in platform-agnostic modules with identical file names on both
platforms, so their behaviour can be validated against one shared set of
fixtures:

```
RingBuffer   fixed capacity, no allocation on write
Scale        domain -> range, and invert
Domain       autoscale target, eased approach, hysteresis
PathBuilder  Fritsch-Carlson monotone cubic tangents
Decimate     min/max and LTTB
Ticks        nice numbers with hysteresis
Clock        frame-rate-independent lerp
HitTest      binary search for scrub position
Theme        accent colour -> derived palette
```

## iOS (Phase 1)

Swift Package `LivelineKit`, Swift 5.9+, iOS 16+. The manifest is at the repo
root (so it installs straight from GitHub via SPM); the sources live under
`ios/Sources/LivelineKit`.

```swift
// Add to any Swift app — no React Native or Nitro required:
.package(url: "https://github.com/lewiscasewell/liveline-mobile", from: "0.0.0")
// then: import LivelineKit
```

```bash
swift build          # builds the maths modules on the host (run at repo root)
swift test           # runs the full XCTest maths suite on the host (no simulator)
```

The pure-maths modules import only `Foundation`/`CoreGraphics`, so they build
and test on macOS without a simulator. All UIKit view code is guarded with
`#if canImport(UIKit)`. To compile the view layer for the device SDK:

```bash
xcodebuild -scheme LivelineKit \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### Example app

```bash
cd examples/ios
xcodebuild -project LivelineDemo.xcodeproj -scheme LivelineDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

A SwiftUI demo rendering a live mean-reverting random walk. The chart's own
`CADisplayLink` interpolates and scrolls at the display refresh rate; the demo's
20 Hz timer models a data feed and is deliberately *not* the render loop.

### API

```swift
Liveline(data: data, value: value)
    .color(.blue)
    .theme(.dark)
    .momentum(.auto)
    .showValue(true)
    .windows([.init(label: "1m", secs: 60)])
    .frame(height: 300)

// imperative — this is what the RN binding will hold
let chart = LivelineView()
chart.color = .systemBlue
chart.push(LivelinePoint(time: t, value: v))
```

## Tooling

- **Format:** `swift format --configuration .swift-format --in-place --recursive ios/Sources`
- **Lint:** `swift format lint --configuration .swift-format --recursive ios/Sources` (clean),
  plus `swiftlint --strict` (config in `.swiftlint.yml`) if SwiftLint is installed.

## Credit

The API shape (prop names, modes, momentum semantics) is ported from
[liveline](https://github.com/) by Benji Taylor, MIT-licensed. See
[`spec/API.md`](spec/API.md) for the mapping and the recorded divergences.

## Licence

MIT.
