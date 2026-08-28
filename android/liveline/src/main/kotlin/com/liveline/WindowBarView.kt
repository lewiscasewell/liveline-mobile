package com.liveline

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import com.liveline.core.WindowBarTokens

/**
 * The interval bar — a row of tappable chips (e.g. 30s / 1m / 5m) with an active
 * indicator, styled from the shared [WindowBarTokens] so it matches iOS/web. Tap
 * a chip to select that window; the host drives the chart's smooth zoom. An
 * optional line/candle toggle sits at the end (see [showModeToggle]).
 */
class WindowBarView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) :
    LinearLayout(context, attrs) {

    data class Window(val label: String, val secs: Double)

    var isDark: Boolean = true
        set(v) { field = v; refresh() }
    var onSelect: ((Double) -> Unit)? = null

    /** Show a line/candle toggle at the end of the bar. */
    var showModeToggle: Boolean = false
        set(v) { field = v; rebuild() }
    /** Current mode reflected by the toggle (`true` = candle). */
    var isCandle: Boolean = false
        set(v) { field = v; refresh() }
    /** Called with `true` for candle, `false` for line when the toggle is tapped. */
    var onModeSelect: ((Boolean) -> Unit)? = null

    private var windows: List<Window> = emptyList()
    private var active: Double = 0.0
    private val chips = ArrayList<TextView>()
    private val modeChips = ArrayList<TextView>()
    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = (v * d)

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER
        setPadding(dp(3f).toInt(), dp(3f).toInt(), dp(3f).toInt(), dp(3f).toInt())
    }

    fun setWindows(list: List<Window>, active: Double) {
        windows = list; this.active = active
        rebuild()
    }

    fun setActive(secs: Double) { active = secs; refresh() }

    private fun makeChip(label: String, onClick: () -> Unit): TextView =
        TextView(context).apply {
            text = label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, WindowBarTokens.FONT_SIZE.toFloat())
            gravity = Gravity.CENTER
            setPadding(dp(10f).toInt(), dp(3f).toInt(), dp(10f).toInt(), dp(3f).toInt())
            setOnClickListener { onClick() }
        }

    private fun rebuild() {
        removeAllViews(); chips.clear(); modeChips.clear()
        for (w in windows) {
            val chip = makeChip(w.label) { active = w.secs; onSelect?.invoke(w.secs); refresh() }
            addView(chip); chips.add(chip)
        }
        if (showModeToggle) {
            if (windows.isNotEmpty()) {
                addView(View(context).apply {
                    background = GradientDrawable().apply { setColor(gray(0.15)) }
                }, LayoutParams(dp(1f).toInt(), dp(16f).toInt()).apply {
                    leftMargin = dp(4f).toInt(); rightMargin = dp(4f).toInt(); gravity = Gravity.CENTER_VERTICAL
                })
            }
            for ((idx, label) in listOf("Line", "Candle").withIndex()) {
                val chip = makeChip(label) { isCandle = idx == 1; onModeSelect?.invoke(idx == 1) }
                addView(chip); modeChips.add(chip)
            }
        }
        refresh()
    }

    private fun gray(alpha: Double): Int {
        val c = if (isDark) 255 else 0
        return Color.argb((alpha * 255).toInt().coerceIn(0, 255), c, c, c)
    }

    private fun indicator() = GradientDrawable().apply {
        cornerRadius = dp(999f); setColor(gray(WindowBarTokens.indicatorAlpha(isDark)))
    }

    private fun refresh() {
        background = GradientDrawable().apply { cornerRadius = dp(999f); setColor(gray(WindowBarTokens.trackAlpha(isDark))) }
        for ((i, chip) in chips.withIndex()) {
            val on = windows[i].secs == active
            chip.setTextColor(gray(if (on) WindowBarTokens.activeAlpha(isDark) else WindowBarTokens.inactiveAlpha(isDark)))
            chip.background = if (on) indicator() else null
        }
        for ((i, chip) in modeChips.withIndex()) {
            val on = (i == 1) == isCandle
            chip.setTextColor(gray(if (on) WindowBarTokens.activeAlpha(isDark) else WindowBarTokens.inactiveAlpha(isDark)))
            chip.background = if (on) indicator() else null
        }
    }
}
