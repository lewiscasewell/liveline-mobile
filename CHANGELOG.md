# Changelog

All notable changes to liveline-mobile are documented here. One version spans all
three artifacts — npm (`liveline-mobile`), Swift Package (`LivelineKit`), and the
Maven Central Android engine (`io.github.lewiscasewell:liveline`).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-08-28

First public release. Pre-1.0: the API is complete but may change before 1.0.

### Added
- Real-time line and candlestick charts, rendered natively on iOS (Swift
  `LivelineKit`, CoreGraphics) and Android (Kotlin, Canvas), with a React Native
  binding via Nitro Modules.
- Smooth streaming updates via imperative `push()` (no React re-render), plus a
  declarative `data` / `value` path.
- Momentum arrows + direction-tinted value badge, live pulse dot, reference line,
  order-book depth, multi-series (equal-peer lines with a legend), degen mode
  (shake + sparks), and a value overlay.
- Native interval bar (`windows`) and an opt-in native line/candle mode toggle
  (`modeToggle` / `onModeChange`), drawn as segmented controls.
- Scrub-to-inspect crosshair with a value/time readout; loading and empty states.
- Theming (light/dark), custom fonts, and full value/time formatting.

[Unreleased]: https://github.com/lewiscasewell/liveline-mobile/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/lewiscasewell/liveline-mobile/releases/tag/v0.1.0
