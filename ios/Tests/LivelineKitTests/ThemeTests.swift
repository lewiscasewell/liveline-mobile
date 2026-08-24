import XCTest

@testable import LivelineKit

final class ThemeTests: XCTestCase {
    // #3b82f6 — liveline's default accent.
    let accent = RGBA(r255: 59, g255: 130, b255: 246)

    func testLineIsAccent() {
        let palette = Theme.palette(accent: accent, theme: .dark)
        XCTAssertEqual(palette.line, accent.withAlpha(1))
        XCTAssertEqual(palette.lineWidth, 2)
    }

    func testFillAlphasMatchReference() {
        let dark = Theme.palette(accent: accent, theme: .dark)
        XCTAssertEqual(dark.fillTop.a, 0.12, accuracy: 1e-12)
        XCTAssertEqual(dark.fillBottom.a, 0, accuracy: 1e-12)
        let light = Theme.palette(accent: accent, theme: .light)
        XCTAssertEqual(light.fillTop.a, 0.08, accuracy: 1e-12)
    }

    func testBackgroundMatchesReference() {
        let dark = Theme.palette(accent: accent, theme: .dark)
        XCTAssertEqual(dark.background, RGBA(r255: 10, g255: 10, b255: 10))
        let light = Theme.palette(accent: accent, theme: .light)
        XCTAssertEqual(light.background, RGBA(r255: 255, g255: 255, b255: 255))
    }

    func testSemanticDotColors() {
        let palette = Theme.palette(accent: accent, theme: .dark)
        // #22c55e green up, #ef4444 red down, accent flat.
        XCTAssertEqual(palette.dotUp, RGBA(r255: 34, g255: 197, b255: 94))
        XCTAssertEqual(palette.dotDown, RGBA(r255: 239, g255: 68, b255: 68))
        XCTAssertEqual(palette.dotFlat, accent.withAlpha(1))
    }

    func testBadgeIsAccentPill() {
        let palette = Theme.palette(accent: accent, theme: .dark)
        XCTAssertEqual(palette.badgeBg, accent.withAlpha(1))
        XCTAssertEqual(palette.badgeText, RGBA(r255: 255, g255: 255, b255: 255))
    }

    func testDashLineIsAccentAt40Percent() {
        let palette = Theme.palette(accent: accent, theme: .dark)
        XCTAssertEqual(palette.dashLine.a, 0.4, accuracy: 1e-12)
        XCTAssertEqual(palette.dashLine.r, accent.r, accuracy: 1e-12)
    }
}
