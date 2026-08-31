# Changelog

## [0.1.1](https://github.com/lewiscasewell/liveline-mobile/compare/v0.1.0...v0.1.1) (2026-08-31)


### Bug Fixes

* **ios:** self-contained RN pod via vendored xcframework ([68844e4](https://github.com/lewiscasewell/liveline-mobile/commit/68844e4a3e2f1fe6dd019463b7f74fca2a77fa41))
* **ios:** vendor the engine as a prebuilt xcframework (self-contained RN pod) ([c55fd7a](https://github.com/lewiscasewell/liveline-mobile/commit/c55fd7af5ac5792bd53ae0b0e14aebbf722cf293))

## 0.1.0 (2026-08-30)

First public release. Pre-1.0: the API is complete but may still change before 1.0.

### Features

* Real-time **line** and **candlestick** charts, rendered natively on iOS (Swift `LivelineKit`, CoreGraphics) and Android (Kotlin, Canvas), with a React Native binding via Nitro Modules.
* Smooth streaming updates via imperative `push()` (no React re-render), plus a declarative `data` / `value` path.
* Momentum arrows and a direction-tinted value badge, live pulse dot, reference line, order-book depth, **multi-series** with a toggle legend, degen mode (shake + sparks), and a value overlay.
* Native **interval bar** (`windows`) and an opt-in native **line/candle toggle** (`modeToggle` / `onModeChange`), drawn as segmented controls.
* Scrub-to-inspect crosshair with a value/time readout; loading and empty states.
* Theming (light/dark), custom fonts, and full value/time formatting.
