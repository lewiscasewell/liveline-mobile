package com.liveline.core

/**
 * Shared design tokens for the interval-bar chrome, so the platform bars stay in
 * lock-step. The bar is grayscale: white on a dark appearance, black on light,
 * at the alphas below. Values mirror web liveline's window-bar styling.
 */
object WindowBarTokens {
    /** Point size for interval labels. */
    const val FONT_SIZE: Double = 11.0

    /** Container/track background alpha. */
    fun trackAlpha(isDark: Boolean): Double = if (isDark) 0.03 else 0.02
    /** Active-button indicator fill alpha. */
    fun indicatorAlpha(isDark: Boolean): Double = if (isDark) 0.06 else 0.035
    /** Active label/icon alpha. */
    fun activeAlpha(isDark: Boolean): Double = if (isDark) 0.7 else 0.55
    /** Inactive label/icon alpha. */
    fun inactiveAlpha(isDark: Boolean): Double = if (isDark) 0.25 else 0.22
}
