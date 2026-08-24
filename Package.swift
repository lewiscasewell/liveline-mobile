// swift-tools-version: 5.9
import PackageDescription

// Manifest at the repo root so LivelineKit is installable straight from GitHub
// via SPM (`.package(url: "…/liveline-mobile")`). Sources stay under `ios/`.
let package = Package(
    name: "LivelineKit",
    // macOS is declared only so the pure-maths modules build and test on the
    // host without a simulator (`swift test`). All UIKit view code is guarded
    // with `#if canImport(UIKit)`. iOS 16 is the real deployment target.
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "LivelineKit", targets: ["LivelineKit"]),
    ],
    targets: [
        .target(
            name: "LivelineKit",
            path: "ios/Sources/LivelineKit"
        ),
        .testTarget(
            name: "LivelineKitTests",
            dependencies: ["LivelineKit"],
            path: "ios/Tests/LivelineKitTests"
        ),
    ]
)
