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

/**
 * The multi-series legend: a row of tappable chips (colour dot + label). Tapping
 * a chip hides/shows that series (the chip dims); the host toggles the chart.
 */
class SeriesLegendView @JvmOverloads constructor(context: Context, attrs: AttributeSet? = null) :
    LinearLayout(context, attrs) {

    data class Item(val id: String, val color: Int, val label: String)

    var isDark: Boolean = true
        set(v) { field = v; refresh() }
    /** Dots only, no labels. */
    var compact: Boolean = false
        set(v) { field = v; setItems(items) }
    var onToggle: ((String) -> Unit)? = null

    private var items: List<Item> = emptyList()
    private val hidden = HashSet<String>()
    private val chips = ArrayList<Pair<String, LinearLayout>>()
    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d

    init { orientation = HORIZONTAL; gravity = Gravity.CENTER; setPadding(dp(4f).toInt(), dp(4f).toInt(), dp(4f).toInt(), dp(4f).toInt()) }

    fun setItems(list: List<Item>) {
        items = list
        hidden.retainAll(list.map { it.id }.toSet())
        removeAllViews(); chips.clear()
        for (item in list) {
            val chip = LinearLayout(context).apply {
                orientation = HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(9f).toInt(), dp(4f).toInt(), dp(9f).toInt(), dp(4f).toInt())
                setOnClickListener {
                    if (hidden.contains(item.id)) hidden.remove(item.id) else hidden.add(item.id)
                    onToggle?.invoke(item.id); refresh()
                }
            }
            val dot = View(context).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(item.color) } }
            chip.addView(dot, LayoutParams(dp(7f).toInt(), dp(7f).toInt()).apply { rightMargin = if (compact) 0 else dp(6f).toInt() })
            if (!compact) chip.addView(TextView(context).apply { text = item.label; setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f) })
            addView(chip)
            chips.add(item.id to chip)
        }
        refresh()
    }

    private fun gray(alpha: Double): Int { val c = if (isDark) 255 else 0; return Color.argb((alpha * 255).toInt(), c, c, c) }

    private fun refresh() {
        background = GradientDrawable().apply { cornerRadius = dp(999f); setColor(gray(if (isDark) 0.04 else 0.03)) }
        for ((id, chip) in chips) {
            chip.alpha = if (hidden.contains(id)) 0.35f else 1f
            (chip.getChildAt(1) as? TextView)?.setTextColor(gray(if (isDark) 0.7 else 0.6))
        }
    }
}
