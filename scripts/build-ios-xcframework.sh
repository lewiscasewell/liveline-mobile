#!/usr/bin/env bash
# Builds LivelineKit.xcframework from the Swift Package and drops it into the RN
# package so its podspec can vendor it. The RN pod ships a prebuilt binary
# framework (rather than depending on a CocoaPods pod) so the engine stays its
# own module with no registry and no Nitro C++/type-name conflicts. iOS-native
# apps consume the same engine via SPM.
#
# Run from the repo root. Requires Xcode. Used by CI at publish time and locally
# before building the RN example on iOS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD="$(mktemp -d)"
DD="$BUILD/dd"
OUT="packages/liveline-mobile/ios/LivelineKit.xcframework"

# SwiftPM library products archive as a static object, so temporarily build the
# product as a dynamic framework (BUILD_LIBRARY_FOR_DISTRIBUTION for a stable
# module interface). The manifest is reverted afterwards.
cleanup() { git checkout -- Package.swift 2>/dev/null || true; rm -rf "$BUILD"; }
trap cleanup EXIT
sed -i.bak 's/\.library(name: "LivelineKit", targets:/.library(name: "LivelineKit", type: .dynamic, targets:/' Package.swift
rm -f Package.swift.bak

frameworks=()
for pair in "iOS:iphoneos" "iOS Simulator:iphonesimulator"; do
  plat="${pair%%:*}"; sdk="${pair##*:}"
  xcodebuild archive -scheme LivelineKit \
    -destination "generic/platform=$plat" \
    -archivePath "$BUILD/$sdk" -derivedDataPath "$DD" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO -quiet
  fw="$BUILD/$sdk.xcarchive/Products/usr/local/lib/LivelineKit.framework"
  # xcodebuild leaves the .swiftmodule out of the archived framework; copy it in
  # so the module is importable.
  mkdir -p "$fw/Modules"
  cp -R "$DD/Build/Intermediates.noindex/ArchiveIntermediates/LivelineKit/BuildProductsPath/Release-$sdk/LivelineKit.swiftmodule" "$fw/Modules/"
  frameworks+=("-framework" "$fw")
done

rm -rf "$OUT"
xcodebuild -create-xcframework "${frameworks[@]}" -output "$OUT"
echo "✅ Built $OUT"
