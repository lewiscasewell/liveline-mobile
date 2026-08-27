# Parity matrix

Source of truth: **liveline** by Benji Taylor — [repo](https://github.com/benjitaylor/liveline)
· [write-up](https://benji.org/liveline). This tracks 1:1 parity of the port
across **Swift** (`LivelineKit`), **Kotlin** (`liveline`), and the **RN** Nitro
binding (delivery on iOS + Android), plus our deliberate mobile additions.

Legend: ✅ done · ⚠️ partial · ❌ missing · ➕ mobile addition (not in web) ·
📄 doc section written (README) · 🎥 video captured.

| Prop / feature | Swift | Kotlin | RN·iOS | RN·Android | 📄 | 🎥 | Notes |
| --- | :--: | :--: | :--: | :--: | :--: | :--: | --- |
| `data` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | backfill |
| `value` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | live feed (or `push()`) |
| `series` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | multi-series |
| `theme` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `color` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | accent |
| `grid` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | Kotlin renderer + Nitro now respect it |
| `badge` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `badgeVariant` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | +`accent` (ours) |
| `badgeTail` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `fill` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `pulse` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `lineWidth` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `momentum` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `scrub` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | press-and-hold on mobile |
| `exaggerate` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `showValue` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `valueMomentumColor` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `degen` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | haptics part ❌ Kotlin |
| `mode` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | line/candle |
| `candles` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `candleWidth` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `liveCandle` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| candle↔line morph (via `mode`) | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ | mode-driven; see divergences |
| `lineMode`/`lineData`/`lineValue` | — | — | — | — | — | — | intentionally not ported — see divergences |
| `onModeChange` | — | — | — | — | — | — | app owns `mode`; no built-in toggle to fire it |
| `onSeriesToggle` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** |
| `seriesToggleCompact` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** — dots-only legend |
| `loading` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `paused` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `emptyText` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `window` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `windows` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | Android bar wired |
| `onWindowChange` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `windowStyle` | ✅ | ⚠️ | ✅ | ⚠️ | ☑ | ☐ | Kotlin has one style |
| `tooltipY` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** |
| `tooltipOutline` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** |
| `orderbook` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `referenceLine` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ |  |
| `lerpSpeed` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `padding` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** — to port |
| `onHover` | — | — | — | — | — | — | intentionally not ported — no pointer/hover on touch |
| `cursor` | — | — | — | — | — | — | intentionally not ported — no pointer/hover on touch |
| formatting: `formatValue`/`formatTime` | ✅ | ⚠️ | — | — | ☑ | ☐ | ours: `valuePrefix/suffix/decimals` |
| `currency` / `locale` / `useGrouping` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** — native NumberFormatter |
| `fontFamily` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `surfaceColor` ➕ | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | mobile addition; **C gap** Android |
| `haptics` ➕ | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | mobile addition; **B/C gap** |
| `paletteOverrides` | ✅ | ❌ | — | — | ☐ | ☐ | advanced (Swift-only API) |

**Plan:** feature-by-feature — verify Swift, bring Kotlin to parity, wire Nitro
on both, write the README doc section (prose + code + video placeholder), verify,
commit. Docs land in `packages/liveline-mobile/README.md`. Videos are captured by
the maintainer and linked (GitHub user-attachments URLs).

## Deliberate divergences

Parity is the goal, but we don't copy the web API where its naming would hurt
more than help. The divergences below are intentional.

- **`lineMode` / `lineData` / `lineValue` — not ported.** In the web API these
  three morph a candle chart into a line, but the names collide badly with props
  that already exist: `lineMode` (a boolean) sits next to `mode: 'line' | 'candle'`
  and only means anything while `mode === 'candle'`; `lineData` / `lineValue`
  shadow `data` / `value` as a *second* parallel feed. We get the same feature
  more simply: the candle↔line **morph is driven by `mode`** — flipping it
  animates the transition, drawing the line from the `data` / `value` the app
  already supplies. So there's one line source, not two, and no confusingly-named
  props.
- **`onModeChange` — not ported.** It exists in the web API to report a *built-in*
  line/candle toggle control. Our library ships no such control — the app owns
  `mode` (e.g. the demo's Line/Candle buttons) — so it already knows when it
  changes and there's nothing for the library to call back.
- **`onHover` / `cursor` — not ported.** Both are pointer/hover concepts with
  no touchscreen equivalent: there's no cursor to style, and "hover" is a
  press-and-hold **scrub** here (see `scrub`), which the app can already read
  from its own gesture handling if it needs the scrubbed point.
- **Number formatting** uses declarative `valuePrefix` / `valueSuffix` /
  `valueDecimals` / `currency` / `locale` / `useGrouping` instead of the web's
  `formatValue` / `formatTime` closures, so formatting stays native (off the JS
  thread). See the Number & time formatting docs.
