import Foundation

/// A colour with straight-alpha components in the range `0...1`.
public struct RGBA: Equatable, Sendable {
    /// Red component, `0...1`.
    public var r: Double
    /// Green component, `0...1`.
    public var g: Double
    /// Blue component, `0...1`.
    public var b: Double
    /// Alpha component, `0...1`.
    public var a: Double

    /// Creates a colour from straight-alpha components.
    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Creates a colour from 0–255 channels and a 0–1 alpha (matches the web
    /// `rgba(r, g, b, a)` helper).
    public init(r255: Double, g255: Double, b255: Double, a: Double = 1) {
        self.init(r: r255 / 255, g: g255 / 255, b: b255 / 255, a: a)
    }

    /// Returns a copy with the alpha replaced.
    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: alpha)
    }
}

/// The full set of colours a chart draws with, derived from one accent colour
/// and a ``LivelineTheme``. Mirrors web liveline's `LivelinePalette` so the two
/// implementations produce identical colours for the same input.
public struct Palette: Equatable, Sendable {
    /// The line stroke (the accent colour).
    public var line: RGBA
    /// Default stroke width in points.
    public var lineWidth: Double

    /// Top of the area fill under the line.
    public var fillTop: RGBA
    /// Bottom of the area fill (transparent accent).
    public var fillBottom: RGBA

    /// Grid line colour.
    public var gridLine: RGBA
    /// Grid value-label colour.
    public var gridLabel: RGBA

    /// Live-dot colour when rising.
    public var dotUp: RGBA
    /// Live-dot colour when falling.
    public var dotDown: RGBA
    /// Live-dot colour when flat (the accent).
    public var dotFlat: RGBA
    /// Pulse glow when rising.
    public var glowUp: RGBA
    /// Pulse glow when falling.
    public var glowDown: RGBA
    /// Pulse glow when flat.
    public var glowFlat: RGBA

    /// Badge outer/backing fill (used by the `minimal` variant and the dot's
    /// white outer circle).
    public var badgeOuterBg: RGBA
    /// Badge drop-shadow colour.
    public var badgeOuterShadow: RGBA
    /// Badge pill fill (the accent, in the `default` variant).
    public var badgeBg: RGBA
    /// Badge text colour.
    public var badgeText: RGBA

    /// Dashed current-value baseline colour (accent @ 0.4).
    public var dashLine: RGBA

    /// Reference-line stroke.
    public var refLine: RGBA
    /// Reference-line label colour.
    public var refLabel: RGBA

    /// Time-axis label colour.
    public var timeLabel: RGBA

    /// Crosshair vertical line colour.
    public var crosshairLine: RGBA
    /// Crosshair tooltip background (also the text-outline colour).
    public var tooltipBg: RGBA
    /// Crosshair tooltip primary text.
    public var tooltipText: RGBA
    /// Crosshair tooltip border.
    public var tooltipBorder: RGBA

    /// The surface the chart is drawn on.
    public var background: RGBA
}

/// Derives a full ``Palette`` from a single accent colour and a theme, matching
/// web liveline's `resolveTheme`. Momentum dot colours are always semantic
/// green/red regardless of accent. The derivation is pure arithmetic so the
/// Swift and Kotlin implementations produce byte-identical palettes.
public enum Theme {
    /// Semantic green used for up-momentum (`#22c55e`).
    public static let up = RGBA(r255: 34, g255: 197, b255: 94)
    /// Semantic red used for down-momentum (`#ef4444`).
    public static let down = RGBA(r255: 239, g255: 68, b255: 68)

    /// Builds the palette for `accent` on the given `theme`.
    public static func palette(accent: RGBA, theme: LivelineTheme) -> Palette {
        let isDark = theme == .dark
        let a = accent
        return Palette(
            line: a.withAlpha(1),
            lineWidth: 2,
            fillTop: a.withAlpha(isDark ? 0.12 : 0.08),
            fillBottom: a.withAlpha(0),
            gridLine: isDark
                ? RGBA(r255: 255, g255: 255, b255: 255, a: 0.06)
                : RGBA(r255: 0, g255: 0, b255: 0, a: 0.06),
            gridLabel: isDark
                ? RGBA(r255: 255, g255: 255, b255: 255, a: 0.4)
                : RGBA(r255: 0, g255: 0, b255: 0, a: 0.35),
            dotUp: up,
            dotDown: down,
            dotFlat: a.withAlpha(1),
            glowUp: up.withAlpha(0.18),
            glowDown: down.withAlpha(0.18),
            glowFlat: a.withAlpha(0.12),
            badgeOuterBg: isDark
                ? RGBA(r255: 40, g255: 40, b255: 40, a: 0.95)
                : RGBA(r255: 255, g255: 255, b255: 255, a: 0.95),
            badgeOuterShadow: isDark
                ? RGBA(r255: 0, g255: 0, b255: 0, a: 0.4)
                : RGBA(r255: 0, g255: 0, b255: 0, a: 0.15),
            badgeBg: a.withAlpha(1),
            badgeText: RGBA(r255: 255, g255: 255, b255: 255),
            dashLine: a.withAlpha(0.4),
            refLine: isDark
                ? RGBA(r255: 255, g255: 255, b255: 255, a: 0.15)
                : RGBA(r255: 0, g255: 0, b255: 0, a: 0.12),
            refLabel: isDark
                ? RGBA(r255: 255, g255: 255, b255: 255, a: 0.45)
                : RGBA(r255: 0, g255: 0, b255: 0, a: 0.4),
            timeLabel: isDark
                ? RGBA(r255: 255, g255: 255, b255: 255, a: 0.35)
                : RGBA(r255: 0, g255: 0, b255: 0, a: 0.3),
            crosshairLine: isDark
                ? RGBA(r255: 255, g255: 255, b255: 255, a: 0.2)
                : RGBA(r255: 0, g255: 0, b255: 0, a: 0.12),
            tooltipBg: isDark
                ? RGBA(r255: 30, g255: 30, b255: 30, a: 0.95)
                : RGBA(r255: 255, g255: 255, b255: 255, a: 0.95),
            tooltipText: isDark
                ? RGBA(r255: 229, g255: 229, b255: 229)
                : RGBA(r255: 26, g255: 26, b255: 26),
            tooltipBorder: isDark
                ? RGBA(r255: 255, g255: 255, b255: 255, a: 0.1)
                : RGBA(r255: 0, g255: 0, b255: 0, a: 0.08),
            background: isDark
                ? RGBA(r255: 10, g255: 10, b255: 10)
                : RGBA(r255: 255, g255: 255, b255: 255)
        )
    }
}
