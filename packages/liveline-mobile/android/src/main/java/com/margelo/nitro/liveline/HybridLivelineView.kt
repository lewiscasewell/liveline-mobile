package com.margelo.nitro.liveline

import android.content.Context
import android.graphics.Color
import android.os.Looper
import android.view.View
import com.liveline.LivelineView
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
    override val view: View get() = chart
    private var lastValue: Double? = null

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
        set(v) { field = v; chart.mode = if (v == LivelineMode.CANDLE) CoreMode.CANDLE else CoreMode.LINE }
    override var candles: Array<CandlePoint>? = null
        set(v) { field = v; applyCandles() }
    override var candleWidth: Double? = null
        set(v) { field = v; applyCandles() }
    override var liveCandle: CandlePoint? = null
        set(v) { field = v; applyCandles() }
    override var color: String? = null
        set(v) { field = v; if (!v.isNullOrEmpty()) runCatching { chart.accent = Color.parseColor(v) } }
    override var theme: LivelineTheme? = null
        set(v) { field = v; chart.theme = if (v == LivelineTheme.LIGHT) CoreTheme.LIGHT else CoreTheme.DARK }
    override var surfaceColor: String? = null
    override var lineWidth: Double? = null
    override var window: Double? = null
        set(v) { field = v; if (v != null && v > 0) chart.windowSeconds = v }
    override var windows: Array<WindowOption>? = null
    override var windowStyle: LivelineWindowStyle? = null
    override var onWindowChange: ((secs: Double) -> Unit)? = null
    override var onModeChange: ((mode: LivelineMode) -> Unit)? = null
    override var grid: Boolean? = null
    override var badge: Boolean? = null
    override var badgeTail: Boolean? = null
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
    override var pulse: Boolean? = null
    override var exaggerate: Boolean? = null
        set(v) { field = v; if (v != null) chart.exaggerate = v }
    override var paused: Boolean? = null
        set(v) { field = v; if (v != null) chart.paused = v }
    override var loading: Boolean? = null
        set(v) { field = v; if (v != null) chart.loading = v }
    override var emptyText: String? = null
    override var showValue: Boolean? = null
        set(v) { field = v; if (v != null) chart.showValue = v }
    override var valueMomentumColor: Boolean? = null
        set(v) { field = v; if (v != null) chart.valueMomentumColor = v }
    override var haptics: Boolean? = null
    override var degen: Boolean? = null
        set(v) { field = v; if (v != null) chart.degen = v }
    override var lerpSpeed: Double? = null
    override var referenceLine: LivelineReference? = null
        set(v) { field = v; chart.referenceLine = v?.let { CoreRef(it.value, it.label) } }
    override var orderbook: LivelineOrderbook? = null
        set(v) { field = v; chart.orderbook = v?.let { coreBook(it) } }
    override var valuePrefix: String? = null
        set(v) { field = v; chart.valuePrefix = v ?: "" }
    override var valueSuffix: String? = null
        set(v) { field = v; chart.valueSuffix = v ?: "" }
    override var valueDecimals: Double? = null
        set(v) { field = v; if (v != null) chart.valueDecimals = v.toInt() }
    override var currency: String? = null
    override var locale: String? = null
    override var useGrouping: Boolean? = null
    override var fontFamily: String? = null

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
