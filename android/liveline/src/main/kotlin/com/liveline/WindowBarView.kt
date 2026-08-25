package com.liveline

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import com.liveline.core.WindowBarTokens

/**
 * The interval bar — a row of tappable chips (e.g. 30s / 1m / 5m) with an active
 * indicator, styled from the shared [WindowBarTokens] so it matches iOS/web. Tap
 * a chip to select that window; the host drives the chart's smooth zoom.
 */
class WindowBarView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) :
    LinearLayout(context, attrs) {

    data class Window(val label: String, val secs: Double)

    var isDark: Boolean = true
        set(v) { field = v; refresh() }
    var onSelect: ((Double) -> Unit)? = null

    private var windows: List<Window> = emptyList()
    private var active: Double = 0.0
    private val chips = ArrayList<TextView>()
    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = (v * d)

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER
        setPadding(dp(3f).toInt(), dp(3f).toInt(), dp(3f).toInt(), dp(3f).toInt())
    }

    fun setWindows(list: List<Window>, active: Double) {
        windows = list; this.active = active
        removeAllViews(); chips.clear()
        for (w in list) {
            val chip = TextView(context).apply {
                text = w.label
                setTextSize(TypedValue.COMPLEX_UNIT_SP, WindowBarTokens.FONT_SIZE.toFloat())
                gravity = Gravity.CENTER
                setPadding(dp(10f).toInt(), dp(3f).toInt(), dp(10f).toInt(), dp(3f).toInt())
                setOnClickListener { this@WindowBarView.active = w.secs; onSelect?.invoke(w.secs); refresh() }
            }
            addView(chip)
            chips.add(chip)
        }
        refresh()
    }

    fun setActive(secs: Double) { active = secs; refresh() }

    private fun gray(alpha: Double): Int {
        val c = if (isDark) 255 else 0
        return Color.argb((alpha * 255).toInt().coerceIn(0, 255), c, c, c)
    }

    private fun refresh() {
        background = GradientDrawable().apply { cornerRadius = dp(999f); setColor(gray(WindowBarTokens.trackAlpha(isDark))) }
        for ((i, chip) in chips.withIndex()) {
            val on = windows[i].secs == active
            chip.setTextColor(gray(if (on) WindowBarTokens.activeAlpha(isDark) else WindowBarTokens.inactiveAlpha(isDark)))
            chip.background = if (on) GradientDrawable().apply { cornerRadius = dp(999f); setColor(gray(WindowBarTokens.indicatorAlpha(isDark))) } else null
        }
    }
}
