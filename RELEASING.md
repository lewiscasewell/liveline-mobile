# Releasing liveline-mobile

> **Status: proposal.** Nothing here is set in stone yet — the repo has never
> been published (npm `0.0.0`, no git tags, no CI). This doc proposes a
> repeatable process and flags the decisions still to make (see
> [Open decisions](#open-decisions)). Tighten it as we do the first release.

## What ships

One repo, three consumable artifacts:

| Artifact | For | How it's consumed | Published? |
| --- | --- | --- | --- |
| **`liveline-mobile`** (npm) | React Native apps | `npm i` + autolinking (ships JS source + `nitrogen/generated` + `ios/` + `android/` + the podspec) | ❌ never (`0.0.0`) |
| **`LivelineKit`** (Swift Package) | native iOS apps | SPM from the GitHub URL at a **git tag** | ❌ no tags yet |
| **Android engine** (`android/liveline-core` + `android/liveline`) | native Android apps | — | ❌ not published (RN-only today) |

The RN package is source-shipped: `package.json` `main` points at `src/index.ts`
and Metro transpiles it; the native code is built by the consumer's autolinking.
The nitrogen-generated files are committed and **must be in the published tarball**.

## Open decisions

These are the "we haven't established this yet" bits. Recommendations included.

1. **Versioning across artifacts.** The podspec tags off `s.version` and SPM
   resolves by git tag, so a single `vX.Y.Z` tag already versions both the pod and
   the Swift package. **Recommend: one semver, one source of truth** — the npm
   `version`, mirrored to `LivelineMobile.podspec` `s.version` and the git tag
   `vX.Y.Z`. (A tiny script or a `version` npm hook can keep the podspec in sync.)
2. **Ship source vs build a `dist/`.** Today `main` is `src/index.ts`. Nitro
   modules conventionally ship source (Metro handles TS), which is simplest.
   **Recommend: keep source-shipping**, but add `types`, a `react-native` field,
   and an `exports` map so tooling resolves types cleanly.
3. **Publish the Android engine to Maven?** Right now Android is RN-only. To let
   non-RN Android apps use it (mirroring the standalone Swift Package), publish
   `liveline-core` + `liveline` to **Maven Central or GitHub Packages** via the
   `maven-publish` Gradle plugin. **Recommend: defer to a later release** — ship
   the RN package + Swift Package first; add Android/Maven when there's demand.
4. **Automation.** No CI yet. **Recommend: manual for the first release**, then a
   GitHub Actions workflow that runs the [pre-flight](#pre-flight-checks) on every
   PR and publishes on a `v*` tag.
5. **Changelog.** **Recommend: hand-written `CHANGELOG.md`** to start; adopt
   changesets/conventional-commits later if release cadence picks up.
6. **npm hygiene.** Decide the npm org/scope, enable 2FA + provenance, and pick
   the initial version (`0.1.0` for a pre-1.0 preview, or `1.0.0` if we're
   committing to the API).

## One-time prep (before the first publish)

- [ ] Add a **`files`** allowlist to `packages/liveline-mobile/package.json` so
      the tarball is exactly: `src/`, `nitrogen/generated/`, `ios/`, `android/`,
      `LivelineMobile.podspec`, `nitro.json`, `README.md`, `package.json`.
      Exclude tests, `.cxx/`, `build/`, `.gradle/`.
- [ ] Add `types`, `react-native`, and an `exports` map (decision 2).
- [ ] Sync mechanism for `version` ↔ podspec `s.version` (decision 1).
- [ ] `LICENSE` present in the package (root `LICENSE` exists; confirm it's shipped).
- [ ] `repository`, `homepage`, `bugs` fields in `package.json`.
- [ ] `npm pack --dry-run` and eyeball the file list.

## Pre-flight checks

Run from the repo root — **all must pass, working tree clean**:

```bash
# 1. Generated code is fresh (no stale nitrogen output)
cd packages/liveline-mobile && npx nitrogen && cd ../..
git diff --exit-code           # nitrogen produced no changes

# 2. Types
cd packages/liveline-mobile && npx tsc --noEmit && cd ../..
cd examples/rn && npx tsc --noEmit && cd ../..

# 3. Engine tests (both platforms, host — no device)
swift test                                   # iOS maths (LivelineKit)
cd android && ./gradlew :liveline-core:test && cd ..   # Kotlin maths

# 4. Both example apps build
cd examples/rn/ios && pod install && cd ../../..        # after any nitro change
xcodebuild -project examples/ios/LivelineDemo.xcodeproj -scheme LivelineDemo \
  -destination 'generic/platform=iOS Simulator' build
cd android && ./gradlew :demo:assembleDebug && cd ..
# + build the RN example on a simulator/emulator and smoke-test the showcase

# 5. Format/lint (Swift)
swift format lint --configuration .swift-format --recursive ios/Sources
```

> Metro needs Node 24; nitrogen must be run with Node 24 too (see
> `rn-dev-loop` notes).

## Release steps

1. **Bump the version** (npm `version` → mirror to podspec `s.version`).
2. **Update `CHANGELOG.md`.**
3. **Commit** the bump: `chore(release): vX.Y.Z`.
4. **Tag + push:** `git tag vX.Y.Z && git push --follow-tags`.
   This is what makes the **pod** and the **Swift Package** resolvable at that
   version (both key off the tag).
5. **GitHub release** for `vX.Y.Z` with the changelog notes (drag in the demo
   videos here too).
6. **Publish npm:** `cd packages/liveline-mobile && npm publish` (add `--otp` if
   2FA). Use `--tag next` for pre-1.0 previews if desired.
7. *(Deferred)* **Android/Maven publish** — once decision 3 lands:
   `cd android && ./gradlew publish`.

## Verify a release

- [ ] `npm pack --dry-run` file list is correct (no tests/build junk).
- [ ] Fresh Expo app: `npm i liveline-mobile react-native-nitro-modules`,
      `expo prebuild`, build iOS + Android, render a chart.
- [ ] Fresh SwiftUI app: add the package by the new tag, `import LivelineKit`,
      render.
- [ ] The tag's podspec resolves (`pod install` in the fresh app finds it).
