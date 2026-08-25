package com.margelo.nitro.liveline

import android.content.Context
import android.view.View
import com.liveline.mobile.LivelineView

/**
 * The Android Nitro HybridView for Liveline. For this first link probe every
 * prop is a plain stub and the view self-renders the engine chart — enough to
 * prove the module builds, autolinks and mounts on screen. Prop wiring to the
 * renderer follows.
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

    // ── Props (stubbed for the probe) ──────────────────────────────────────────
    override var data: Array<LivelinePoint>? = null
    override var series: Array<LivelineSeries>? = null
    override var value: Double? = null
    override var mode: LivelineMode? = null
    override var candles: Array<CandlePoint>? = null
    override var candleWidth: Double? = null
    override var liveCandle: CandlePoint? = null
    override var color: String? = null
    override var theme: LivelineTheme? = null
    override var surfaceColor: String? = null
    override var lineWidth: Double? = null
    override var window: Double? = null
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

    // ── Methods (no-op for the probe) ──────────────────────────────────────────
    override fun push(point: LivelinePoint, seriesId: String?) {}
    override fun pushOrderbook(orderbook: LivelineOrderbook) {}
}
