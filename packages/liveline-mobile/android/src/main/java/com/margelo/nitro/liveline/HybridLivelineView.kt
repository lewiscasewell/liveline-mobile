package com.margelo.nitro.liveline

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import com.liveline.LivelineView
import com.liveline.SeriesLegendView
import com.liveline.WindowBarView
import com.liveline.core.BadgeVariant as CoreBadge
import com.liveline.core.LivelineCandle as CoreCandle
import com.liveline.core.LivelineMode as CoreMode
import com.liveline.core.LivelineTheme as CoreTheme
import com.liveline.core.Momentum as CoreMomentum
import com.liveline.core.OrderbookData as CoreBook
import com.liveline.core.OrderbookLevel as CoreLevel
import com.liveline.core.ReferenceLine as CoreRef

/**
 * The Android Nitro HybridView for Liveline: it maps the RN props/methods onto
 * the shared `com.liveline.LivelineView` renderer. Props arrive on the UI thread
 * via the ViewManager's Fabric `updateState`; the imperative methods (`push`,
 * `pushOrderbook`) are called from the JS thread, so they hop to main.
 */
class HybridLivelineView(context: Context) : HybridLivelineSpec() {
    companion object {
        init {
            // Load the C++ library before the super constructor wires the C++ part.
            LivelineMobileOnLoad.initializeNative()
        }
    }

    private val chart = LivelineView(context)
    private val windowBar = WindowBarView(context).apply { visibility = View.GONE }
    private val seriesLegend = SeriesLegendView(context).apply { visibility = View.GONE }
    // Vertical container: the legend (shown only for multi-series) on top, the
    // chart filling, the interval bar (shown only when `windows` is set) below —
    // mirroring the iOS container.
    private val container = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        val dp = resources.displayMetrics.density
        addView(
            seriesLegend,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = (8 * dp).toInt() },
        )
        addView(chart, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        addView(
            windowBar,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.CENTER_HORIZONTAL; topMargin = (8 * dp).toInt() },
        )
    }
    override val view: View get() = container
    private var lastValue: Double? = null

    init {
        windowBar.onSelect = { secs ->
            chart.windowSeconds = secs
            onWindowChange?.invoke(secs)
        }
        windowBar.onModeSelect = { candle ->
            chart.mode = if (candle) CoreMode.CANDLE else CoreMode.LINE
            onModeChange?.invoke(if (candle) LivelineMode.CANDLE else LivelineMode.LINE)
        }
        seriesLegend.onToggle = { id ->
            val visible = chart.toggleSeries(id)
            onSeriesToggle?.invoke(id, visible)
        }
    }

    private fun refreshLegend() {
        val info = chart.seriesInfo()
        if (info.isEmpty()) { seriesLegend.visibility = View.GONE; return }
        seriesLegend.visibility = View.VISIBLE
        seriesLegend.setItems(info.map { SeriesLegendView.Item(it.first, it.second, it.third) })
    }

    private fun refreshWindowBar() {
        val w = windows
        val show = !w.isNullOrEmpty() || modeToggle == true
        if (!show) { windowBar.visibility = View.GONE; return }
        windowBar.visibility = View.VISIBLE
        windowBar.showModeToggle = modeToggle == true
        if (!w.isNullOrEmpty()) windowBar.setWindows(w.map { WindowBarView.Window(it.label, it.secs) }, window ?: w.first().secs)
        else windowBar.setWindows(emptyList(), window ?: 0.0)
    }

    private fun corePoint(p: LivelinePoint) = com.liveline.core.LivelinePoint(p.time, p.value)
    private fun coreCandle(c: CandlePoint) = CoreCandle(c.time, c.open, c.high, c.low, c.close)
    private fun coreLevel(l: LivelineOrderbookLevel) = CoreLevel(l.price, l.size)
    private fun coreBook(b: LivelineOrderbook) =
        CoreBook(b.bids.map { coreLevel(it) }, b.asks.map { coreLevel(it) })

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else chart.post(block)
    }

    private fun applyCandles() {
        val c = candles ?: return
        chart.setCandles(c.map { coreCandle(it) }, liveCandle?.let { coreCandle(it) }, candleWidth ?: 1.0)
    }

    /** Builds the value formatter from currency/locale/grouping/prefix/suffix/
     *  decimals, mirroring the iOS binding's NumberFormatter logic. */
    private fun rebuildFormatter() {
        val loc = locale?.takeIf { it.isNotEmpty() }?.let { java.util.Locale.forLanguageTag(it) }
            ?: java.util.Locale.getDefault()
        val cur = currency
        if (!cur.isNullOrEmpty()) {
            // Currency style provides the symbol/placement and the currency's own
            // fraction digits; prefix/suffix/decimals don't apply (matches iOS).
            val nf = java.text.NumberFormat.getCurrencyInstance(loc)
            runCatching { nf.currency = java.util.Currency.getInstance(cur) }
            nf.isGroupingUsed = useGrouping ?: true
            chart.formatValue = { nf.format(it) }
        } else {
            val nf = java.text.NumberFormat.getNumberInstance(loc)
            val d = (valueDecimals ?: 2.0).toInt()
            nf.minimumFractionDigits = d
            nf.maximumFractionDigits = d
            nf.isGroupingUsed = useGrouping ?: true
            val pre = valuePrefix ?: ""
            val suf = valueSuffix ?: ""
            chart.formatValue = { pre + nf.format(it) + suf }
        }
        chart.invalidate()
    }

    /** Resolves an RN font-family name to a Typeface (bundled fonts via
     *  ReactFontManager; falls back to a system family). */
    private fun resolveTypeface(family: String): Typeface? = runCatching {
        com.facebook.react.common.assets.ReactFontManager.getInstance()
            .getTypeface(family, Typeface.NORMAL, chart.context.assets)
    }.getOrElse { runCatching { Typeface.create(family, Typeface.NORMAL) }.getOrNull() }

    // ── Props ───────────────────────────────────────────────────────────────
    override var data: Array<LivelinePoint>? = null
        set(v) { field = v; if (v != null) chart.setData(v.map { corePoint(it) }) }
    override var series: Array<LivelineSeries>? = null
        set(v) {
            field = v
            if (v != null) chart.setSeries(v.map { s ->
                LivelineView.SeriesInput(
                    s.id,
                    runCatching { Color.parseColor(s.color) }.getOrDefault(chart.accent),
                    s.label,
                    s.data.map { corePoint(it) },
                )
            })
            refreshLegend()
        }
    override var value: Double? = null
        set(v) {
            field = v
            if (v != null && v != lastValue) {
                lastValue = v
                chart.push(com.liveline.core.LivelinePoint(System.currentTimeMillis() / 1000.0, v))
            }
        }
    override var mode: LivelineMode? = null
        set(v) {
            field = v
            chart.mode = if (v == LivelineMode.CANDLE) CoreMode.CANDLE else CoreMode.LINE
            windowBar.isCandle = v == LivelineMode.CANDLE
        }
    override var modeToggle: Boolean? = null
        set(v) { field = v; refreshWindowBar() }
    override var candles: Array<CandlePoint>? = null
        set(v) { field = v; applyCandles() }
    override var candleWidth: Double? = null
        set(v) { field = v; applyCandles() }
    override var liveCandle: CandlePoint? = null
        set(v) { field = v; applyCandles() }
    override var color: String? = null
        set(v) { field = v; if (!v.isNullOrEmpty()) runCatching { chart.accent = Color.parseColor(v) } }
    override var theme: LivelineTheme? = null
        set(v) {
            field = v
            chart.theme = if (v == LivelineTheme.LIGHT) CoreTheme.LIGHT else CoreTheme.DARK
            windowBar.isDark = v != LivelineTheme.LIGHT
            seriesLegend.isDark = v != LivelineTheme.LIGHT
        }
    override var surfaceColor: String? = null
        set(v) {
            field = v
            chart.surfaceColor = v?.takeIf { it.isNotEmpty() }?.let { runCatching { Color.parseColor(it) }.getOrNull() }
        }
    override var lineWidth: Double? = null
        set(v) { field = v; if (v != null && v > 0) chart.lineWidth = v }
    override var window: Double? = null
        set(v) { field = v; if (v != null && v > 0) { chart.windowSeconds = v; windowBar.setActive(v) } }
    override var windows: Array<WindowOption>? = null
        set(v) { field = v; refreshWindowBar() }
    // The Android interval bar has a single (pill) style for now; the `windowStyle`
    // variants (rounded/text) are honoured on iOS.
    override var windowStyle: LivelineWindowStyle? = null
    override var onWindowChange: ((secs: Double) -> Unit)? = null
    override var onModeChange: ((mode: LivelineMode) -> Unit)? = null
    override var grid: Boolean? = null
        set(v) { field = v; if (v != null) chart.grid = v }
    override var badge: Boolean? = null
        set(v) { field = v; if (v != null) chart.badge = v }
    override var badgeTail: Boolean? = null
        set(v) { field = v; if (v != null) chart.badgeTail = v }
    override var badgeVariant: LivelineBadgeVariant? = null
        set(v) {
            field = v
            chart.badgeVariant = when (v) {
                LivelineBadgeVariant.MINIMAL -> CoreBadge.MINIMAL
                LivelineBadgeVariant.ACCENT -> CoreBadge.ACCENT
                else -> CoreBadge.DEFAULT
            }
        }
    override var momentum: LivelineMomentum? = null
        set(v) {
            field = v
            chart.momentum = when (v) {
                LivelineMomentum.OFF -> CoreMomentum.OFF
                LivelineMomentum.UP -> CoreMomentum.UP
                LivelineMomentum.DOWN -> CoreMomentum.DOWN
                LivelineMomentum.FLAT -> CoreMomentum.FLAT
                else -> CoreMomentum.AUTO
            }
        }
    override var fill: Boolean? = null
        set(v) { field = v; if (v != null) chart.fill = v }
    override var scrub: Boolean? = null
        set(v) { field = v; if (v != null) chart.scrub = v }
    override var tooltipY: Double? = null
        set(v) { field = v; if (v != null) chart.tooltipY = v }
    override var tooltipOutline: Boolean? = null
        set(v) { field = v; if (v != null) chart.tooltipOutline = v }
    override var padding: LivelinePadding? = null
        set(v) {
            field = v
            chart.padTopOverride = v?.top; chart.padRightOverride = v?.right
            chart.padBottomOverride = v?.bottom; chart.padLeftOverride = v?.left
        }
    override var seriesToggleCompact: Boolean? = null
        set(v) { field = v; if (v != null) seriesLegend.compact = v }
    override var onSeriesToggle: ((id: String, visible: Boolean) -> Unit)? = null
    override var pulse: Boolean? = null
        set(v) { field = v; if (v != null) chart.pulse = v }
    override var exaggerate: Boolean? = null
        set(v) { field = v; if (v != null) chart.exaggerate = v }
    override var paused: Boolean? = null
        set(v) { field = v; if (v != null) chart.paused = v }
    override var loading: Boolean? = null
        set(v) { field = v; if (v != null) chart.loading = v }
    override var emptyText: String? = null
        set(v) { field = v; if (v != null) chart.emptyText = v }
    override var showValue: Boolean? = null
        set(v) { field = v; if (v != null) chart.showValue = v }
    override var valueMomentumColor: Boolean? = null
        set(v) { field = v; if (v != null) chart.valueMomentumColor = v }
    override var haptics: Boolean? = null
        set(v) { field = v; if (v != null) chart.haptics = v }
    override var degen: Boolean? = null
        set(v) { field = v; if (v != null) chart.degen = v }
    override var lerpSpeed: Double? = null
        set(v) { field = v; if (v != null && v > 0) chart.lerpSpeed = v }
    override var referenceLine: LivelineReference? = null
        set(v) { field = v; chart.referenceLine = v?.let { CoreRef(it.value, it.label) } }
    override var orderbook: LivelineOrderbook? = null
        set(v) { field = v; chart.orderbook = v?.let { coreBook(it) } }
    override var valuePrefix: String? = null
        set(v) { field = v; chart.valuePrefix = v ?: ""; rebuildFormatter() }
    override var valueSuffix: String? = null
        set(v) { field = v; chart.valueSuffix = v ?: ""; rebuildFormatter() }
    override var valueDecimals: Double? = null
        set(v) { field = v; if (v != null) chart.valueDecimals = v.toInt(); rebuildFormatter() }
    override var currency: String? = null
        set(v) { field = v; rebuildFormatter() }
    override var locale: String? = null
        set(v) { field = v; rebuildFormatter() }
    override var useGrouping: Boolean? = null
        set(v) { field = v; rebuildFormatter() }
    override var fontFamily: String? = null
        set(v) {
            field = v
            chart.numberTypeface = v?.takeIf { it.isNotEmpty() }?.let { resolveTypeface(it) }
        }

    // ── Methods ─────────────────────────────────────────────────────────────
    override fun push(point: LivelinePoint, seriesId: String?) {
        val p = corePoint(point)
        onMain { if (seriesId != null) chart.pushSeries(seriesId, p) else chart.push(p) }
    }

    override fun pushOrderbook(orderbook: LivelineOrderbook) {
        val b = coreBook(orderbook)
        onMain { chart.orderbook = b }
    }
}
