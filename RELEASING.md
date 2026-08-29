# Releasing liveline-mobile

> **Status: plumbing + CI wired, not yet published.** The publishing config,
> signing, and the release-please pipeline are set up and verified with local
> dry-runs; nothing is on npm/Maven yet. **One release ships all three artifacts
> together**, versioned by a single semver / git tag. First public version:
> **`0.1.0`** (pre-1.0 — the API is complete but we reserve the right to change
> it before 1.0), seeded by hand, then automated from `0.2.0`.

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

Done on the `release-plumbing` branch:

- [x] **`files`** allowlist in `packages/liveline-mobile/package.json` — tarball is
      `src/`, `nitrogen/generated/`, `ios/`, `android/src` + `android/build.gradle`
      + `android/CMakeLists.txt`, `LivelineMobile.podspec`, `react-native.config.js`,
      `nitro.json`, `README.md`, `LICENSE`. (Allowlisting the specific `android/*`
      paths — not the whole dir — drops `build/` and `.cxx/` with no `.npmignore`.)
      Verified with `npm pack --dry-run` (106 files, ~76 kB).
- [x] `types`, `react-native`, and an `exports` map (decision 2).
- [x] **`maven-publish` + signing** via the `com.vanniktech.maven.publish` plugin
      in `android/liveline-core` and `android/liveline` (group
      `io.github.lewiscasewell`, artifacts `liveline-core` / `liveline`, Central
      Portal target). `liveline` depends on `liveline-core` via `api`, so the
      published POM lists it as a `compile` dep. Verified with `publishToMavenLocal`
      (AAR + jar + sources + javadoc + correct POMs). Signing auto-enables only
      once a real `signing.gnupg.keyName` is set (placeholder ⇒ unsigned local
      dry-runs work).
- [x] **Single-source version**: both podspecs and the Android Gradle build read
      `packages/liveline-mobile/package.json` at configure time, so `npm version`
      moves all three. Git tags are `vX.Y.Z` (podspecs use `:tag => "v#{s.version}"`).
      No `postversion` hook needed.
- [x] `LICENSE` copied into the package (shipped in the tarball).
- [x] `repository`, `homepage`, `bugs`, `author` fields in `package.json`.
- [x] `CHANGELOG.md` seeded with `0.1.0`.

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

## Automated releases (the pipeline)

Once `0.1.0` is seeded (below), releases are automated via
[release-please](https://github.com/googleapis/release-please):

1. **Merge feature PRs to `main`** using [Conventional Commits](https://www.conventionalcommits.org/):
   `feat:` → minor, `fix:` → patch, `feat!:` / `BREAKING CHANGE:` → major (in
   0.x a breaking change bumps minor). This is the version *and* the changelog.
2. `release.yml` keeps a **"Release vX.Y.Z" PR** open with the computed version +
   generated changelog. Nothing is published while it sits there.
3. **Merge the Release PR** → release-please tags `vX.Y.Z` + cuts the GitHub
   release, which gates the two publish jobs: `npm publish --provenance` and
   `./gradlew publishAndReleaseToMavenCentral`.

`ci.yml` runs on every PR/push: `tsc` (package + example), nitrogen-freshness,
Kotlin + Swift engine tests, Android library compile, and swift-format lint.

### GitHub secrets (Settings → Secrets and variables → Actions)

The CI equivalents of your local `~/.gradle/gradle.properties`:

| Secret | Value |
| --- | --- |
| `NPM_TOKEN` | an npm **automation** access token (npmjs → Access Tokens) |
| `MAVEN_CENTRAL_USERNAME` | Central Portal user-token username |
| `MAVEN_CENTRAL_PASSWORD` | Central Portal user-token password |
| `SIGNING_KEY` | the **armored private** GPG key: `gpg --export-secret-keys --armor <KEY_ID>` |
| `SIGNING_KEY_PASSWORD` | the key's passphrase (empty for the no-passphrase key) |

CI signs with the in-memory key (`signingInMemoryKey`); locally you keep using
the gpg agent (`signing.gnupg.keyName`) — the Gradle build accepts either.

## Release steps

> These are the **manual** path — used once to seed `0.1.0` (worth doing by hand
> to watch the first-ever publish to a new npm name + Central namespace), and as
> a fallback if CI is ever unavailable. After `0.1.0`, use the pipeline above.

1. **Bump the version:** `cd packages/liveline-mobile && npm version X.Y.Z`
   (the podspecs and the Android Gradle build read this file, so all three move).
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
   (signs + uploads `liveline-core` and `liveline` to a Central Portal staging
   deployment; verify and **Publish** it in the portal UI). Use
   `publishAndReleaseToMavenCentral` instead to skip the manual release step once
   you trust the pipeline.

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
