# Releasing liveline-mobile

> **Status: the plan.** Repo has never been published (npm `0.0.0`, no git tags,
> no CI). **One release ships all three artifacts together**, versioned by a
> single semver / git tag. First public version: **`0.1.0`** (pre-1.0 — the API
> is complete but we reserve the right to change it before 1.0).

## What ships

One repo, three consumable artifacts — **released together under one version**:

| Artifact | For | How it's consumed | Registry |
| --- | --- | --- | --- |
| **`liveline-mobile`** (npm) | React Native apps | `npm i` + autolinking (ships JS source + `nitrogen/generated` + `ios/` + `android/` + the podspec) | npm |
| **`LivelineKit`** (Swift Package) | native iOS apps | SPM from the GitHub URL at the **git tag** | GitHub tag (+ the CocoaPod, via the podspec) |
| **`liveline` engine** (`liveline-core` + `liveline`) | native Android apps | Gradle dependency | Maven Central (namespace `io.github.lewiscasewell`) |

The RN package is source-shipped: `package.json` `main` points at `src/index.ts`
and Metro transpiles it; the native code is built by the consumer's autolinking.
The nitrogen-generated files are committed and **must be in the published tarball**.

## Decisions (made)

These were previously open; here's the call and the one-line "why" in plain terms.

1. **One version for everything.** npm `version` = podspec `s.version` = git tag
   `vX.Y.Z`. *Why:* the pod and Swift Package already key off the git tag, so one
   number/one tag is the least error-prone. A `version`/`postversion` npm hook
   syncs the podspec + Gradle version automatically.
2. **Ship TS source (no build step).** Keep `main: src/index.ts`; add `types` +
   `react-native` + `exports`. *Why:* Metro transpiles TS anyway, and Nitro
   modules are source-shipped — a `dist/` build is just a maintenance liability.
3. **Android ships too, via Maven Central** (namespace `io.github.lewiscasewell`).
   *Why:* you asked for all three together, and the GitHub-based Central namespace
   is self-service (no manual approval) — the easiest path to a *public* artifact
   consumers can pull with no extra repo/auth. `maven-publish` + signing, wired in
   Gradle.
4. **First release is manual; CI is a fast-follow.** *Why:* get one clean release
   by hand, then codify it as a GitHub Action (pre-flight on PRs, publish on `v*`).
5. **Hand-written `CHANGELOG.md`.** *Why:* low ceremony now; adopt changesets
   later only if cadence demands it.
6. **`0.1.0`, unscoped name `liveline-mobile`, provenance on** (once CI publishes).

## Prerequisites — only you can set these up

Accounts and keys I can't create for you. One-time:

- [ ] **npm:** an account with publish rights to `liveline-mobile` (confirm the
      name is free: `npm view liveline-mobile` should 404), `npm login`, 2FA on.
- [ ] **Maven Central:** a [Central Portal](https://central.sonatype.com) account,
      verify the `io.github.lewiscasewell` namespace (it checks you own the GitHub
      account — near-instant), and a **GPG key** for signing (publish a public key
      to a keyserver). Put the credentials + key in `~/.gradle/gradle.properties`
      (never commit them).
- [ ] **GitHub:** rights to push tags and create Releases (you have this).

Once those exist, everything below is scriptable and I can wire it up.

## One-time prep (before the first publish)

- [ ] Add a **`files`** allowlist to `packages/liveline-mobile/package.json` so
      the tarball is exactly: `src/`, `nitrogen/generated/`, `ios/`, `android/`,
      `LivelineMobile.podspec`, `nitro.json`, `README.md`, `package.json`.
      Exclude tests, `.cxx/`, `build/`, `.gradle/`.
- [ ] Add `types`, `react-native`, and an `exports` map (decision 2).
- [ ] Wire **`maven-publish` + signing** into `android/liveline-core` and
      `android/liveline` `build.gradle` (group `io.github.lewiscasewell`,
      artifacts `liveline-core` / `liveline`) — decision 3.
- [ ] Sync mechanism for `version` ↔ podspec `s.version` ↔ Gradle version
      (a `postversion` npm hook, single source of truth) — decision 1.
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
   2FA).
7. **Publish Android to Maven Central:** `cd android && ./gradlew publishToMavenCentral`
   (signs + uploads `liveline-core` and `liveline` at the same version).

Steps 4–7 are what CI will do on a `v*` tag once it's set up; until then, by hand.

## Verify a release

- [ ] `npm pack --dry-run` file list is correct (no tests/build junk).
- [ ] Fresh Expo app: `npm i liveline-mobile react-native-nitro-modules`,
      `expo prebuild`, build iOS + Android, render a chart.
- [ ] Fresh SwiftUI app: add the package by the new tag, `import LivelineKit`,
      render.
- [ ] Fresh Android app: `implementation "io.github.lewiscasewell:liveline:X.Y.Z"`
      resolves from Maven Central, `LivelineView` renders.
- [ ] The tag's podspec resolves (`pod install` in the fresh app finds it).
