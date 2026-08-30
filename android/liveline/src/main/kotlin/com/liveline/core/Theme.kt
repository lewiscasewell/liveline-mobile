package com.liveline.core

/** A colour with straight-alpha components in the range `0..1`. */
data class Rgba(val r: Double, val g: Double, val b: Double, val a: Double = 1.0) {
    /** Returns a copy with the alpha replaced. */
    fun withAlpha(alpha: Double): Rgba = Rgba(r, g, b, alpha)

    companion object {
        /** From 0–255 channels and a 0–1 alpha (matches web's `rgba(...)`). */
        fun from255(r255: Double, g255: Double, b255: Double, a: Double = 1.0): Rgba =
            Rgba(r255 / 255, g255 / 255, b255 / 255, a)
    }
}

/**
 * The full set of colours a chart draws with, derived from one accent colour and
 * a [LivelineTheme]. Mirrors web liveline's `LivelinePalette` so the platforms
 * produce identical colours for the same input.
 */
data class Palette(
    val line: Rgba,
    val lineWidth: Double,
    val fillTop: Rgba,
    val fillBottom: Rgba,
    val gridLine: Rgba,
    val gridLabel: Rgba,
    val dotUp: Rgba,
    val dotDown: Rgba,
    val dotFlat: Rgba,
    val glowUp: Rgba,
    val glowDown: Rgba,
    val glowFlat: Rgba,
    val badgeOuterBg: Rgba,
    val badgeOuterShadow: Rgba,
    val badgeBg: Rgba,
    val badgeText: Rgba,
    val dashLine: Rgba,
    val refLine: Rgba,
    val refLabel: Rgba,
    val timeLabel: Rgba,
    val crosshairLine: Rgba,
    val tooltipBg: Rgba,
    val tooltipText: Rgba,
    val tooltipBorder: Rgba,
    val background: Rgba,
)

/**
 * Derives a full [Palette] from a single accent colour and a theme, matching web
 * liveline's `resolveTheme`. Momentum dot colours are always semantic green/red.
 * Pure arithmetic, so Swift and Kotlin produce identical palettes.
 */
object Theme {
    /** Semantic green used for up-momentum (`#22c55e`). */
    val up = Rgba.from255(34.0, 197.0, 94.0)
    /** Semantic red used for down-momentum (`#ef4444`). */
    val down = Rgba.from255(239.0, 68.0, 68.0)

    /** Builds the palette for [accent] on the given [theme]. */
    fun palette(accent: Rgba, theme: LivelineTheme): Palette {
        val isDark = theme == LivelineTheme.DARK
        val a = accent
        return Palette(
            line = a.withAlpha(1.0),
            lineWidth = 2.0,
            fillTop = a.withAlpha(if (isDark) 0.12 else 0.08),
            fillBottom = a.withAlpha(0.0),
            gridLine = if (isDark) Rgba.from255(255.0, 255.0, 255.0, 0.06) else Rgba.from255(0.0, 0.0, 0.0, 0.06),
            gridLabel = if (isDark) Rgba.from255(255.0, 255.0, 255.0, 0.4) else Rgba.from255(0.0, 0.0, 0.0, 0.35),
            dotUp = up,
            dotDown = down,
            dotFlat = a.withAlpha(1.0),
            glowUp = up.withAlpha(0.18),
            glowDown = down.withAlpha(0.18),
            glowFlat = a.withAlpha(0.12),
            badgeOuterBg = if (isDark) Rgba.from255(40.0, 40.0, 40.0, 0.95) else Rgba.from255(255.0, 255.0, 255.0, 0.95),
            badgeOuterShadow = if (isDark) Rgba.from255(0.0, 0.0, 0.0, 0.4) else Rgba.from255(0.0, 0.0, 0.0, 0.15),
            badgeBg = a.withAlpha(1.0),
            badgeText = Rgba.from255(255.0, 255.0, 255.0),
            dashLine = a.withAlpha(0.4),
            refLine = if (isDark) Rgba.from255(255.0, 255.0, 255.0, 0.15) else Rgba.from255(0.0, 0.0, 0.0, 0.12),
            refLabel = if (isDark) Rgba.from255(255.0, 255.0, 255.0, 0.45) else Rgba.from255(0.0, 0.0, 0.0, 0.4),
            timeLabel = if (isDark) Rgba.from255(255.0, 255.0, 255.0, 0.35) else Rgba.from255(0.0, 0.0, 0.0, 0.3),
            crosshairLine = if (isDark) Rgba.from255(255.0, 255.0, 255.0, 0.2) else Rgba.from255(0.0, 0.0, 0.0, 0.12),
            tooltipBg = if (isDark) Rgba.from255(30.0, 30.0, 30.0, 0.95) else Rgba.from255(255.0, 255.0, 255.0, 0.95),
            tooltipText = if (isDark) Rgba.from255(229.0, 229.0, 229.0) else Rgba.from255(26.0, 26.0, 26.0),
            tooltipBorder = if (isDark) Rgba.from255(255.0, 255.0, 255.0, 0.1) else Rgba.from255(0.0, 0.0, 0.0, 0.08),
            background = if (isDark) Rgba.from255(10.0, 10.0, 10.0) else Rgba.from255(255.0, 255.0, 255.0),
        )
    }
}
