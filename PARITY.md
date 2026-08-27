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
| `momentum` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `scrub` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ | press-and-hold on mobile |
| `exaggerate` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `showValue` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `valueMomentumColor` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `degen` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ | haptics part ❌ Kotlin |
| `mode` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ | line/candle |
| `candles` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `candleWidth` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `liveCandle` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `lineMode`+`lineData`+`lineValue` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** — candle↔line morph |
| `onModeChange` | ⚠️ | ❌ | ⚠️ | ❌ | ☐ | ☐ |  |
| `onSeriesToggle` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** |
| `seriesToggleCompact` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** — dots-only legend |
| `loading` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `paused` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `emptyText` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `window` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `windows` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ | Android bar wired |
| `onWindowChange` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `windowStyle` | ✅ | ⚠️ | ✅ | ⚠️ | ☐ | ☐ | Kotlin has one style |
| `tooltipY` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** |
| `tooltipOutline` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** |
| `orderbook` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `referenceLine` | ✅ | ✅ | ✅ | ✅ | ☐ | ☐ |  |
| `lerpSpeed` | ✅ | ✅ | ✅ | ✅ | ☑ | ☐ | **B/C gap** |
| `padding` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | **A gap** — to port |
| `onHover` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | map to `onScrub` |
| `cursor` | ❌ | ❌ | ❌ | ❌ | ☐ | ☐ | to port (map to scrub crosshair) |
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
