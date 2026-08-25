package com.liveline.core

import kotlin.test.Test
import kotlin.test.assertEquals

class ThemeTest {
    @Test
    fun lineIsAccentAndFillFadesToTransparent() {
        val accent = Rgba.from255(59.0, 130.0, 246.0) // #3b82f6
        val p = Theme.palette(accent, LivelineTheme.DARK)
        assertEquals(accent.withAlpha(1.0), p.line)
        assertEquals(0.12, p.fillTop.a, 1e-12)
        assertEquals(0.0, p.fillBottom.a, 1e-12)
    }

    @Test
    fun momentumColoursAreSemanticGreenRed() {
        val p = Theme.palette(Rgba.from255(59.0, 130.0, 246.0), LivelineTheme.DARK)
        assertEquals(Rgba.from255(34.0, 197.0, 94.0), p.dotUp)
        assertEquals(Rgba.from255(239.0, 68.0, 68.0), p.dotDown)
    }

    @Test
    fun themeSwitchesBackground() {
        val accent = Rgba.from255(59.0, 130.0, 246.0)
        assertEquals(Rgba.from255(10.0, 10.0, 10.0), Theme.palette(accent, LivelineTheme.DARK).background)
        assertEquals(Rgba.from255(255.0, 255.0, 255.0), Theme.palette(accent, LivelineTheme.LIGHT).background)
    }
}
