package com.margelo.nitro.liveline

import android.content.Context
import android.graphics.Color
import android.os.Looper
import android.view.View
import com.liveline.LivelineView
import com.liveline.core.LivelineTheme as CoreTheme

/**
 * The Android Nitro HybridView for Liveline: it maps the RN props/methods onto
 * the shared `com.liveline.LivelineView` renderer. Line-mode essentials are
 * wired (data, value, colour, theme, window, push); the remaining props are
 * stubs until the renderer grows those features.
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

    // TEMPORARY: Nitro's Fabric prop/method delivery for this view isn't wired on
    // Android yet — the view falls back to RN's interop path, which doesn't
    // deliver Nitro props (data/value/push/hybridRef). Until that's fixed, seed a
    // demo feed so the chart still renders; it's disabled the instant any real
    // prop or push arrives.
    private val demoHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var demoValue = 100.0
    private var demoActive = true

    init {
        val now = System.currentTimeMillis() / 1000.0
        var v = 100.0
        chart.setData(
            (0 until 150).map { i ->
                v += (100 - v) * 0.02 + (Math.random() - 0.5) * 0.36
                com.liveline.core.LivelinePoint(now - 30 + i / 149.0 * 30, v)
            })
        demoValue = v
        demoHandler.post(object : Runnable {
            override fun run() {
                if (!demoActive) return
                demoValue += (100 - demoValue) * 0.012 + (Math.random() - 0.5) * 0.12
                chart.push(com.liveline.core.LivelinePoint(System.currentTimeMillis() / 1000.0, demoValue))
                demoHandler.postDelayed(this, 100)
            }
        })
    }

    private fun stopDemo() {
        if (demoActive) { demoActive = false; demoHandler.removeCallbacksAndMessages(null) }
    }

    // ── Props ───────────────────────────────────────────────────────────────
    override var data: Array<LivelinePoint>? = null
        set(v) {
            field = v
            if (v != null) { stopDemo(); chart.setData(v.map { corePoint(it) }) }
        }
    override var series: Array<LivelineSeries>? = null
    override var value: Double? = null
        set(v) {
            field = v
            if (v != null && v != lastValue) {
                lastValue = v
                stopDemo()
                chart.push(com.liveline.core.LivelinePoint(System.currentTimeMillis() / 1000.0, v))
            }
        }
    override var mode: LivelineMode? = null
    override var candles: Array<CandlePoint>? = null
    override var candleWidth: Double? = null
    override var liveCandle: CandlePoint? = null
    override var color: String? = null
        set(v) {
            field = v
            if (!v.isNullOrEmpty()) runCatching { chart.accent = Color.parseColor(v) }
        }
    override var theme: LivelineTheme? = null
        set(v) {
            field = v
            chart.theme = if (v == LivelineTheme.LIGHT) CoreTheme.LIGHT else CoreTheme.DARK
        }
    override var surfaceColor: String? = null
    override var lineWidth: Double? = null
    override var window: Double? = null
        set(v) {
            field = v
            if (v != null && v > 0) chart.windowSeconds = v
        }
    override var windows: Array<WindowOption>? = null
    override var windowStyle: LivelineWindowStyle? = null
    override var onWindowChange: ((secs: Double) -> Unit)? = null
    override var onModeChange: ((mode: LivelineMode) -> Unit)? = null
    override var grid: Boolean? = null
    override var badge: Boolean? = null
    override var badgeTail: Boolean? = null
    override var badgeVariant: LivelineBadgeVariant? = null
    override var momentum: LivelineMomentum? = null
    override var fill: Boolean? = null
    override var scrub: Boolean? = null
    override var pulse: Boolean? = null
    override var exaggerate: Boolean? = null
    override var paused: Boolean? = null
    override var loading: Boolean? = null
    override var emptyText: String? = null
    override var showValue: Boolean? = null
    override var valueMomentumColor: Boolean? = null
    override var haptics: Boolean? = null
    override var degen: Boolean? = null
    override var lerpSpeed: Double? = null
    override var referenceLine: LivelineReference? = null
    override var orderbook: LivelineOrderbook? = null
    override var valuePrefix: String? = null
    override var valueSuffix: String? = null
    override var valueDecimals: Double? = null
    override var currency: String? = null
    override var locale: String? = null
    override var useGrouping: Boolean? = null
    override var fontFamily: String? = null

    // ── Methods ─────────────────────────────────────────────────────────────
    override fun push(point: LivelinePoint, seriesId: String?) {
        // seriesId (multi-series) not rendered yet; route the primary line.
        if (seriesId != null) return
        stopDemo()
        // Called from the JS thread; the renderer's buffer is read on the UI
        // thread each frame, so hop to main to avoid a data race.
        val p = corePoint(point)
        if (Looper.myLooper() == Looper.getMainLooper()) chart.push(p) else chart.post { chart.push(p) }
    }

    override fun pushOrderbook(orderbook: LivelineOrderbook) {}
}
