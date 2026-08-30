# Changelog

## 0.1.0 (2026-08-30)


### Features

* add tooltipY/tooltipOutline/padding; scaffold onSeriesToggle/seriesToggleCompact ([4a2493b](https://github.com/lewiscasewell/liveline-mobile/commit/4a2493b2ec403ff30808dad80320bc9e6ca2ae06))
* **android:** currency/locale/grouping formatting, fontFamily, surfaceColor, haptics (Kotlin parity) ([bc0bf5a](https://github.com/lewiscasewell/liveline-mobile/commit/bc0bf5a47f537f9624c56cc9e9c4948c59a08b25))
* **android:** honour badge/badgeTail/pulse/lineWidth/lerpSpeed/emptyText (Kotlin parity) ([50ae7e2](https://github.com/lewiscasewell/liveline-mobile/commit/50ae7e271a81556a4fcc5f6b22f97b83782a6e5f))
* **android:** honour the `grid` prop (Kotlin parity) + add PARITY.md tracker ([25bf47f](https://github.com/lewiscasewell/liveline-mobile/commit/25bf47f4868223e278189ca64c20e409061f0153))
* **android:** wire the interval-bar props (windows/windowStyle/onWindowChange) on the Nitro view ([fd6efdb](https://github.com/lewiscasewell/liveline-mobile/commit/fd6efdb95045cbb0cd563634ef43770ddb4a632e))
* deliver the multi-series legend (onSeriesToggle + seriesToggleCompact) ([b902282](https://github.com/lewiscasewell/liveline-mobile/commit/b902282d0ca7e9c60bb1aa23e4a005f707e18291))
* haptics default true on every platform (still optional) ([73d75e1](https://github.com/lewiscasewell/liveline-mobile/commit/73d75e1d5c06052f25294da93f4acba183f3ab00))
* native line/candle mode toggle (modeToggle prop) ([5878953](https://github.com/lewiscasewell/liveline-mobile/commit/5878953add5f0fadd319a15149915a8c9fe5ea3d))


### Bug Fixes

* **android:** deliver Nitro props/methods to the native Liveline view ([079a51a](https://github.com/lewiscasewell/liveline-mobile/commit/079a51a39eae2ac2396240debf9474606720b589))


### Documentation

* add Android (Kotlin) usage section + de-stale the Android platform notes ([601045c](https://github.com/lewiscasewell/liveline-mobile/commit/601045c0ce347c6e5a10a05b17e1fa9d3d0ef2fa))
* add the Number & time formatting group + surfaceColor + haptics entries. ([bc0bf5a](https://github.com/lewiscasewell/liveline-mobile/commit/bc0bf5a47f537f9624c56cc9e9c4948c59a08b25))
* add their Feature-reference entries (+ badgeVariant); update PARITY.md. ([50ae7e2](https://github.com/lewiscasewell/liveline-mobile/commit/50ae7e271a81556a4fcc5f6b22f97b83782a6e5f))
* correct the value framing — it's the state-update re-render that costs, not the prop ([3cb54a6](https://github.com/lewiscasewell/liveline-mobile/commit/3cb54a6192d658a7a8c16c0dd8fe97210cea7bf6))
* de-dupe README (gallery + recipes) and record windowStyle as a native-styling divergence ([6482e6d](https://github.com/lewiscasewell/liveline-mobile/commit/6482e6d9d85d18446ee5020a8bfeeaaef9b55dd9))
* document Android, highlight the mobile-native additions, add video/blog placeholders ([df2885d](https://github.com/lewiscasewell/liveline-mobile/commit/df2885d881a370634f8132d7c455386190053f32))
* Feature-reference entries for the already-at-parity features (group 3) ([72f6b00](https://github.com/lewiscasewell/liveline-mobile/commit/72f6b002da242f317bdbe7f2a245e59aa89448e5))
* Feature-reference entries for tooltipY/tooltipOutline, padding, the morph, and the legend pair ([67d9879](https://github.com/lewiscasewell/liveline-mobile/commit/67d98797da747ec5c143688e6032c9fb275e4915))
* haptics is on Android now (drop stale "Android next"); tidy morph notes ([a70c869](https://github.com/lewiscasewell/liveline-mobile/commit/a70c869f975af09785f09eb70933cb99c1e372e7))
* install for npm/yarn/pnpm/bun + accurate 2026 Expo story ([62bead3](https://github.com/lewiscasewell/liveline-mobile/commit/62bead3eccab49baa8be41f52d19a5d3d2313766))
* link Benji Taylor's original liveline write-up (benji.org/liveline) ([2cc35d6](https://github.com/lewiscasewell/liveline-mobile/commit/2cc35d62e88c5dd7a7917dfd5dfdd8206ee53ccf))
* make surfaceColor's web-extension + transparent-default explicit ([8730a9d](https://github.com/lewiscasewell/liveline-mobile/commit/8730a9da3050e21152d5be416cb3c119c3549a86))
* make value's re-render cost explicit (JSDoc + README), recommend push() with data ([c4be331](https://github.com/lewiscasewell/liveline-mobile/commit/c4be331ffbec03bc2d6c3eaf84a3633e0431c061))
* mark Expo as the recommended install path ([66ca0ac](https://github.com/lewiscasewell/liveline-mobile/commit/66ca0ac0bae9e1d6b2d72dbddaceb60d0672e687))
* start the Feature reference gallery (live-data + appearance basics) ([afbf4b8](https://github.com/lewiscasewell/liveline-mobile/commit/afbf4b81848d3d6a36202a763e5176feaaab7630))
* the Android interval bar (windows/onWindowChange) is now wired ([fdb7f77](https://github.com/lewiscasewell/liveline-mobile/commit/fdb7f77926e49c1ab0d021d40d033194d774254b))


### Refactors

* **android:** ship one Maven artifact + fix the published RN package ([e71d0d5](https://github.com/lewiscasewell/liveline-mobile/commit/e71d0d55cb2a90feb56eba83d617c99f3abc4075))


### Chores

* release 0.1.0 ([c71e70e](https://github.com/lewiscasewell/liveline-mobile/commit/c71e70ee08ec48852ca1b0a7e06870d1fb8657ab))

## Changelog

All notable changes to liveline-mobile are documented here. One version spans all
three artifacts — npm (`liveline-mobile`), Swift Package (`LivelineKit`), and the
Maven Central Android engine (`io.github.lewiscasewell:liveline`).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
