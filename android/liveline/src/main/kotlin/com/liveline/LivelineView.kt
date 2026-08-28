package com.liveline

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.format.DateFormat
import android.util.AttributeSet
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import com.liveline.core.AutoRange
import com.liveline.core.BadgeVariant
import com.liveline.core.Clock
import com.liveline.core.Domain
import com.liveline.core.Interpolate
import com.liveline.core.Intervals
import com.liveline.core.LivelineCandle
import com.liveline.core.LivelineMode
import com.liveline.core.LivelinePoint
import com.liveline.core.LivelineTheme
import com.liveline.core.Momentum
import com.liveline.core.MomentumDetect
import com.liveline.core.OrderbookData
import com.liveline.core.PathBuilder
import com.liveline.core.Point
import com.liveline.core.ReferenceLine
import com.liveline.core.Rgba
import com.liveline.core.Theme
import com.liveline.core.Ticks
import com.liveline.core.Trend
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The Android line-mode renderer for liveline — a faithful port of the Swift
 * `LivelineView` draw pipeline onto a `Canvas`: grid + value axis, line + fill +
 * dashed baseline, reference line, momentum-tinted tailed badge + endpoint
 * arrows, the value overlay, a press-and-hold crosshair, and a scrolling time
 * axis. All maths and colours come from `com.liveline.core`.
 */
class LivelineView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs), Choreographer.FrameCallback {

    // ── Public API ──────────────────────────────────────────────────────────
    var accent: Int = Color.parseColor("#3b82f6")
        set(v) { field = v; rebuildPalette() }
    var theme: LivelineTheme = LivelineTheme.DARK
        set(v) { field = v; rebuildPalette() }
    var windowSeconds: Double = 30.0
    var momentum: Momentum = Momentum.AUTO
    var badgeVariant: BadgeVariant = BadgeVariant.DEFAULT
    var badge: Boolean = true
    /** The pointed tail on the badge pill (ignored for the minimal variant). */
    var badgeTail: Boolean = true
    var showValue: Boolean = false
    var valueMomentumColor: Boolean = false
    var fill: Boolean = true
    /** Y-axis grid lines + value labels (the time axis is always drawn). */
    var grid: Boolean = true
    var pulse: Boolean = true
    var lineWidth: Double = 2.0
    /** Interpolation speed toward the latest value (0–1). */
    var lerpSpeed: Double = 0.08
    /** Shown centred when there is no data (and not loading). */
    var emptyText: String = "No data to display"
    var exaggerate: Boolean = false
    var loading: Boolean = false
    var paused: Boolean = false
    var scrub: Boolean = true
    var degen: Boolean = false
    var referenceLine: ReferenceLine? = null
    var valuePrefix: String = ""
    var valueSuffix: String = ""
    var valueDecimals: Int = 2
    /** Overrides the prefix/suffix/decimals formatting (used for the Nitro
     *  binding's currency/locale/grouping formatter). Applied to the badge, value
     *  overlay, crosshair and Y-axis labels. */
    var formatValue: ((Double) -> String)? = null
    /** Opaque card background; `null` = transparent (the default). */
    var surfaceColor: Int? = null
        set(v) { field = v; invalidate() }
    /** Haptic feedback on degen bursts. */
    var haptics: Boolean = true
    /** Custom typeface for numbers/labels; `null` = monospace (tabular digits). */
    var numberTypeface: Typeface? = null
        set(v) { field = v; applyTypeface() }
    /** Vertical offset (points) of the crosshair tooltip text. */
    var tooltipY: Double = 14.0
    /** Stroke an outline behind the crosshair tooltip text for legibility. */
    var tooltipOutline: Boolean = true
    /** Per-side chart-inset overrides in points; `null` keeps the default. */
    var padTopOverride: Double? = null
    var padRightOverride: Double? = null
    var padBottomOverride: Double? = null
    var padLeftOverride: Double? = null
    var mode: LivelineMode = LivelineMode.LINE
    var candleWidth: Double = 1.0

    /** Order-book depth; resting sizes stream up behind the line. Also folds the
     *  change in total depth into an eased churn signal driving the stream speed. */
    var orderbook: OrderbookData? = null
        set(v) {
            if (v != null) {
                val total = v.bids.sumOf { it.size } + v.asks.sumOf { it.size }
                if (orderbookLastTotal >= 0 && total > 0) {
                    val inst = min(1.0, abs(total - orderbookLastTotal) / total * 5)
                    orderbookChurn = orderbookChurn * 0.6 + inst * 0.4
                }
                orderbookLastTotal = total
            }
            field = v
        }

    private var candles: List<LivelineCandle> = emptyList()
    private var liveCandle: LivelineCandle? = null
    private var liveBull = 0.5

    private class ObLabel(val text: String, val x: Float, val spawnY: Float, val isBid: Boolean, val weight: Double, var yOffset: Float = 0f)
    private val obLabels = ArrayList<ObLabel>()
    private var obSpawnClock = 0.0
    private var orderbookLastTotal = -1.0
    private var orderbookChurn = 0.0

    private class DegenParticle(var x: Double, var y: Double, var vx: Double, var vy: Double, var life: Double, val maxLife: Double)
    private val degenParticles = ArrayList<DegenParticle>()
    private var degenShake = 0.0
    private var degenBaseline = 0.0
    private var degenBaselineInit = false
    private var degenArmed = true

    /** Sets the OHLC candles + the currently-forming live candle (candle mode). */
    fun setCandles(candles: List<LivelineCandle>, live: LivelineCandle?, width: Double) {
        this.candles = candles; this.liveCandle = live; this.candleWidth = width
    }

    // ── Multi-series ──────────────────────────────────────────────────────────
    /** One equal-peer line for multi-series mode. */
    class SeriesInput(val id: String, val color: Int, val label: String?, val data: List<LivelinePoint>)
    private class Series(val id: String, val color: Int, val label: String?, val buffer: MutableList<LivelinePoint>, var visible: Boolean, var displayValue: Double, var lastCommit: Double, var labelY: Float = 0f) {
        // Eased toward visible ? 1 : 0, so toggled lines fade in/out.
        var visAlpha: Double = if (visible) 1.0 else 0.0
    }
    private val series = ArrayList<Series>()
    val isMultiSeries: Boolean get() = series.isNotEmpty()

    /** A non-empty list switches to multi-series mode (replaces data/value). */
    fun setSeries(inputs: List<SeriesInput>) {
        val wasVisible = series.associate { it.id to it.visible }
        series.clear()
        for (inp in inputs) series.add(Series(inp.id, inp.color, inp.label, ArrayList(inp.data), wasVisible[inp.id] ?: true, inp.data.lastOrNull()?.value ?: 0.0, inp.data.lastOrNull()?.time ?: -Double.MAX_VALUE))
    }

    fun pushSeries(id: String, point: LivelinePoint) {
        val s = series.firstOrNull { it.id == id } ?: return
        val bucket = windowSeconds / 300.0
        if (s.buffer.isEmpty() || point.time - s.lastCommit >= bucket) { s.buffer.add(point); s.lastCommit = point.time; if (s.buffer.size > 8192) s.buffer.removeAt(0) } else s.buffer[s.buffer.size - 1] = point
    }

    /** Flips a series' visibility; returns the new visible state. */
    fun toggleSeries(id: String): Boolean {
        val s = series.firstOrNull { it.id == id } ?: return true
        s.visible = !s.visible
        return s.visible
    }
    /** (id, colour, label) for building a legend. */
    fun seriesInfo(): List<Triple<String, Int, String>> = series.map { Triple(it.id, it.color, it.label ?: it.id) }

    fun setData(points: List<LivelinePoint>) {
        buffer.clear()
        buffer.addAll(points)
        points.lastOrNull()?.let { value = it.value; displayValue = it.value }
        lastCommitSec = points.lastOrNull()?.time ?: 0.0
    }

    fun push(point: LivelinePoint) {
        value = point.value
        val bucket = windowSeconds / 300.0
        if (buffer.isEmpty() || point.time - lastCommitSec >= bucket) {
            buffer.add(point); lastCommitSec = point.time
            if (buffer.size > 8192) buffer.removeAt(0)
        } else buffer[buffer.size - 1] = point
    }

    // ── State ───────────────────────────────────────────────────────────────
    private val buffer = ArrayList<LivelinePoint>()
    private val domain = Domain()
    private var value = 0.0
    private var displayValue = 0.0
    private var gridInterval = 0.0
    private var lastFrameMs = 0.0
    private var lastCommitSec = 0.0
    private var frameDt = Clock.FRAME_MS
    private var badgeY = 0f
    private var badgeGreen = 0.5
    private var arrowUp = 0.0
    private var arrowDown = 0.0
    private var loadingAlpha = 0.0
    private var pauseNow = 0.0
    private var scrubbing = false
    private var hoverX = 0f
    private var scrubAmount = 0.0
    // Smooth window (interval) transition, log-interpolated over 750ms.
    private var displayWindow = 0.0
    private var modeProgress = 0.0
    private var windowInited = false
    private var windowFrom = 0.0
    private var windowTo = 0.0
    private var windowStartMs = 0.0

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d

    private var palette = Theme.palette(accent.toRgba(), theme)

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(0.5f) }
    private val scrubFadePaint = Paint().apply { style = Paint.Style.FILL }
    private val dashPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1f); pathEffect = DashPathEffect(floatArrayOf(dp(3f), dp(3f)), 0f) }
    private val refPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1f) }
    private val refDashPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1f); pathEffect = DashPathEffect(floatArrayOf(dp(4f), dp(4f)), 0f) }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(11f); typeface = Typeface.MONOSPACE }
    private val refLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(11f); textAlign = Paint.Align.CENTER }
    private val timeLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(11f); typeface = Typeface.MONOSPACE; textAlign = Paint.Align.CENTER }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(0.5f) }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1.5f) }
    private val dotOuter = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val dotInner = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val badgeTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(13f); typeface = Typeface.MONOSPACE }
    private val overlayPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(22f); typeface = Typeface.MONOSPACE }
    private val chevronPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(2.5f); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val crossPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1f) }
    private val crossDot = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val tipPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(13f) }
    private val fadePaint = Paint().apply { style = Paint.Style.FILL }
    private val candleStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }
    private val candleFill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val obPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(11f); typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD); textAlign = Paint.Align.LEFT }
    private val sparkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val seriesLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(13f); typeface = Typeface.MONOSPACE }
    // Multi-series layout (set during drawMultiSeries so helpers can map to px).
    private var msPadL = 0f; private var msPadT = 0f; private var msChartH = 0f; private var msChartW = 0f; private var msW = 0f
    private var msLeft = 0.0; private var msRight = 0.0; private var msMax = 0.0; private var msRange = 1.0
    private fun mtoX(t: Double) = msPadL + ((t - msLeft) / (msRight - msLeft)).toFloat() * msChartW
    private fun mtoY(v: Double) = msPadT + ((msMax - v) / msRange).toFloat() * msChartH
    private val bull = Theme.up
    private val bear = Theme.down
    private fun blend(a: Rgba, b: Rgba, t: Double) = Rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)

    private fun rebuildPalette() {
        palette = Theme.palette(accent.toRgba(), theme)
        linePaint.color = palette.line.toInt(); linePaint.strokeWidth = dp(lineWidth.toFloat())
        // Grid a touch lighter than the raw palette line so it reads like web/iOS.
        gridPaint.color = palette.gridLine.withAlpha(palette.gridLine.a * 0.7).toInt()
        axisPaint.color = palette.gridLine.withAlpha(palette.gridLine.a * 0.7).toInt()
        labelPaint.color = palette.gridLabel.toInt(); timeLabelPaint.color = palette.timeLabel.toInt()
        badgeTextPaint.color = palette.badgeText.toInt(); dotOuter.color = palette.badgeOuterBg.toInt()
        refLabelPaint.color = palette.refLabel.toInt()
    }

    init { rebuildPalette() }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); Choreographer.getInstance().postFrameCallback(this) }
    override fun onDetachedFromWindow() { super.onDetachedFromWindow(); Choreographer.getInstance().removeFrameCallback(this) }

    override fun doFrame(frameTimeNanos: Long) {
        val nowMs = frameTimeNanos / 1_000_000.0
        frameDt = if (lastFrameMs == 0.0) Clock.FRAME_MS else (nowMs - lastFrameMs).coerceIn(1.0, 64.0)
        lastFrameMs = nowMs
        invalidate()
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!scrub) return false
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { scrubbing = true; hoverX = e.x; parent?.requestDisallowInterceptTouchEvent(true); return true }
            MotionEvent.ACTION_MOVE -> { hoverX = e.x; return true }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { scrubbing = false; parent?.requestDisallowInterceptTouchEvent(false); return true }
        }
        return false
    }

    private fun fmt(v: Double): String =
        formatValue?.invoke(v) ?: (valuePrefix + String.format("%.${valueDecimals}f", v) + valueSuffix)

    /** Applies the custom typeface (or monospace) to every text paint. */
    private fun applyTypeface() {
        val tf = numberTypeface ?: Typeface.MONOSPACE
        labelPaint.typeface = tf; timeLabelPaint.typeface = tf; badgeTextPaint.typeface = tf
        overlayPaint.typeface = tf; tipPaint.typeface = tf; seriesLabelPaint.typeface = tf
        invalidate()
    }

    /** Smoothly log-interpolates the visible span toward [windowSeconds]. */
    private fun advanceWindow(nowMs: Double) {
        if (!windowInited) { displayWindow = windowSeconds; windowTo = windowSeconds; windowInited = true; return }
        if (windowTo != windowSeconds) { windowFrom = displayWindow; windowTo = windowSeconds; windowStartMs = nowMs }
        if (displayWindow != windowTo) {
            val t = ((nowMs - windowStartMs) / 750.0).coerceIn(0.0, 1.0)
            val eased = 0.5 - 0.5 * cos(t * PI)
            val lf = ln(windowFrom); val lt = ln(windowTo)
            displayWindow = exp(lf + (lt - lf) * eased)
            if (t >= 1.0) displayWindow = windowTo
        }
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        if (w <= 0 || h <= 0) return
        surfaceColor?.let { canvas.drawColor(it) }
        val nowMs = System.nanoTime() / 1_000_000.0
        val dt = frameDt
        advanceWindow(nowMs)
        val span = displayWindow

        loadingAlpha = Clock.lerp(loadingAlpha, if (loading) 1.0 else 0.0, 0.1, dt).coerceIn(0.0, 1.0)
        scrubAmount = Clock.lerp(scrubAmount, if (scrubbing) 1.0 else 0.0, 0.2, dt).coerceIn(0.0, 1.0)
        modeProgress = Clock.lerp(modeProgress, if (mode == LivelineMode.CANDLE) 1.0 else 0.0, 0.1, dt)
        if (modeProgress < 0.002) modeProgress = 0.0
        if (modeProgress > 0.998) modeProgress = 1.0
        degenAdvance(dt)

        if (isMultiSeries) { drawMultiSeries(canvas, w, h, span, now = System.currentTimeMillis() / 1000.0, dt, nowMs); return }

        val padL = padLeftOverride?.let { dp(it.toFloat()) } ?: dp(8f)
        val padR = padRightOverride?.let { dp(it.toFloat()) } ?: dp(64f)
        val padT = padTopOverride?.let { dp(it.toFloat()) } ?: (if (showValue) dp(40f) else dp(12f))
        val padB = padBottomOverride?.let { dp(it.toFloat()) } ?: dp(30f)
        val chartW = w - padL - padR; val chartH = h - padT - padB

        // Freeze `now` while paused so the line stops scrolling.
        val realNow = System.currentTimeMillis() / 1000.0
        if (!paused) pauseNow = realNow
        val now = if (paused) pauseNow else realNow
        val isCandle = modeProgress > 0.0 && (candles.isNotEmpty() || liveCandle != null)
        // Momentum chevrons sit just right of the live dot; widen the right-edge
        // buffer so they clear the badge instead of hiding behind it (mirrors iOS
        // currentWinBuffer). One source of truth so the crosshair mapping agrees.
        val rightBuf = if (!isCandle && badge && momentum != Momentum.OFF) max(0.05, dp(37f).toDouble() / chartW) else 0.05
        val rightEdge = now + span * rightBuf
        val leftEdge = rightEdge - span

        if (isCandle) {
            drawCandleFrame(canvas, w, padL, padR, padT, chartH, span, now, leftEdge, rightEdge, nowMs, dt, modeProgress)
            return
        }
        if (buffer.size < 2) {
            if (buffer.isEmpty() && !loading && emptyText.isNotEmpty()) {
                labelPaint.textAlign = Paint.Align.CENTER
                labelPaint.textSize = dp(13f)
                labelPaint.color = palette.timeLabel.withAlpha(palette.timeLabel.a * 0.9).toInt()
                canvas.drawText(emptyText, w / 2f, padT + chartH / 2f, labelPaint)
                labelPaint.textAlign = Paint.Align.LEFT
                labelPaint.textSize = dp(11f)
            }
            return
        }

        var startIdx = 0
        for (i in buffer.indices) if (buffer[i].time >= leftEdge) { startIdx = max(0, i - 1); break }
        val visible = ArrayList<LivelinePoint>()
        for (i in startIdx until buffer.size) if (buffer[i].time <= now) visible.add(buffer[i])
        if (visible.size < 2) return

        val speed = Domain.adaptiveSpeed(value, displayValue, domain.minVal, domain.maxVal, lerpSpeed)
        displayValue = Clock.lerp(displayValue, value, speed, dt)
        val target = AutoRange.compute(visible.map { it.value }, displayValue, referenceLine?.value, exaggerate)
        domain.update(target, speed, dt, chartH.toDouble())
        val minV = domain.minVal; val maxV = domain.maxVal; val range = domain.valRange
        fun toX(t: Double) = padL + ((t - leftEdge) / (rightEdge - leftEdge)).toFloat() * chartW
        fun toY(v: Double) = padT + ((maxV - v) / range).toFloat() * chartH

        // Degen: shake the whole frame (everything shakes together).
        val degenShaken = degen
        if (degenShaken) {
            canvas.save()
            if (degenShake > 0) canvas.translate(((Math.random() * 2 - 1) * degenShake).toFloat(), ((Math.random() * 2 - 1) * degenShake).toFloat())
        }

        // 1. Reference line.
        referenceLine?.let { drawReferenceLine(canvas, it, padL, padR, padT, w, chartW, chartH) { v -> toY(v) } }

        // 2. Grid + value labels.
        val pxPerUnit = chartH / range
        gridInterval = Ticks.pickInterval(range, pxPerUnit.toDouble(), dp(36f).toDouble(), gridInterval)
        if (grid && gridInterval > 0) {
            var g = ceil(minV / gridInterval) * gridInterval
            labelPaint.textAlign = Paint.Align.LEFT
            while (g <= maxV) {
                val y = toY(g)
                canvas.drawLine(padL, y, padL + chartW, y, gridPaint)
                canvas.drawText(fmt(g), padL + chartW + dp(6f), y + dp(4f), labelPaint)
                g += gridInterval
            }
        }

        val trend = if (momentum == Momentum.OFF) Trend.FLAT else when (momentum) {
            Momentum.UP -> Trend.UP; Momentum.DOWN -> Trend.DOWN; Momentum.FLAT -> Trend.FLAT
            else -> MomentumDetect.detect(visible)
        }

        // 2b. Orderbook: resting sizes stream up behind the price line.
        if (orderbook != null) {
            val mMag = min(1.0, abs(value - displayValue) / max(range * 0.15, 1e-9))
            drawOrderbook(canvas, padL, padT, chartH, mMag, 1.0, dt)
        }

        val endX = toX(now); val endY = toY(displayValue)
        if (degen) degenTrigger(endX, endY, displayValue, range, dt)
        val pts = ArrayList<Point>(visible.size)
        for (p in visible) pts.add(Point(toX(p.time).toDouble(), toY(p.value).toDouble()))
        pts[pts.size - 1] = Point(endX.toDouble(), endY.toDouble())

        // 3. Dashed baseline.
        dashPaint.color = palette.dashLine.toInt()
        canvas.drawLine(padL, endY, endX, endY, dashPaint)

        // 4. Line + fill. While `loading`, the line is a grey, breathing version of
        // itself that reveals to the accent colour (and the fill fades in) as
        // loading ends — matching the iOS reveal.
        val reveal = 1.0 - loadingAlpha
        val breath = 0.22 + 0.08 * sin(nowMs / 1200.0 * PI)
        val lineAlpha = if (reveal < 1.0) breath + (1 - breath) * reveal else 1.0
        val strokeCol = if (reveal < 1.0) {
            val t = min(1.0, reveal * 3); val g = palette.gridLabel; val l = palette.line
            Rgba(g.r + (l.r - g.r) * t, g.g + (l.g - g.g) * t, g.b + (l.b - g.b) * t)
        } else palette.line

        val path = Path()
        path.moveTo(pts[0].x.toFloat(), pts[0].y.toFloat())
        for (s in PathBuilder.monotoneSegments(pts)) path.cubicTo(s.control1.x.toFloat(), s.control1.y.toFloat(), s.control2.x.toFloat(), s.control2.y.toFloat(), s.end.x.toFloat(), s.end.y.toFloat())
        if (fill && reveal > 0.01) {
            val f = Path(path); f.lineTo(pts.last().x.toFloat(), padT + chartH); f.lineTo(pts.first().x.toFloat(), padT + chartH); f.close()
            fillPaint.shader = LinearGradient(0f, padT, 0f, padT + chartH, palette.fillTop.toInt(), palette.fillBottom.toInt(), Shader.TileMode.CLAMP)
            fillPaint.alpha = (255 * reveal).toInt().coerceIn(0, 255)
            canvas.drawPath(f, fillPaint)
        }
        linePaint.color = strokeCol.withAlpha(strokeCol.a * lineAlpha).toInt()
        canvas.drawPath(path, linePaint)
        linePaint.color = palette.line.toInt()  // restore for the scrub-fade + reuse below

        // 4b. While scrubbing, fade the line to the RIGHT of the crosshair.
        if (scrubAmount > 0.02) {
            val hx = hoverX.coerceIn(padL, padL + chartW)
            scrubFadePaint.color = palette.background.withAlpha(palette.background.a * scrubAmount * 0.55).toInt()
            canvas.drawRect(hx, padT, padL + chartW, padT + chartH, scrubFadePaint)
        }

        // 5. Time axis.
        drawTimeAxis(canvas, w, padL, padR, padT + chartH, leftEdge, rightEdge, span, dt)

        // 6. Left-edge fade — over the line AND the time labels (full height), so
        // the labels dissolve into the background on the left (matches iOS).
        val fadeW = dp(56f)
        fadePaint.shader = LinearGradient(padL, 0f, padL + fadeW, 0f, palette.background.toInt(), palette.background.withAlpha(0.0).toInt(), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, padL + fadeW, h, fadePaint)

        // 7. Live dot + pulse — always the line colour (momentum shows via the
        // badge + chevrons, not the dot).
        val dim = scrubAmount * 0.7
        val headColor = palette.line
        // Fade the dot / pulse / arrows / badge in with the loading reveal (iOS).
        val dotReveal = ((reveal - 0.3) / 0.7).coerceIn(0.0, 1.0)
        if (pulse && dim < 0.3 && reveal > 0.6) {
            val t = (nowMs % 1500.0) / 900.0
            if (t < 1) { ringPaint.color = headColor.withAlpha(headColor.a * 0.35 * (1 - t) * (1 - dim * 3)).toInt(); canvas.drawCircle(endX, endY, dp(9f) + (t * dp(12f).toDouble()).toFloat(), ringPaint) }
        }
        val dotA = (1 - dim) * dotReveal
        dotOuter.alpha = (255 * dotA).toInt().coerceIn(0, 255)
        canvas.drawCircle(endX, endY, dp(6.5f), dotOuter)
        dotInner.color = headColor.withAlpha(headColor.a * dotA).toInt()
        canvas.drawCircle(endX, endY, dp(3.5f), dotInner)

        // 8. Momentum arrows.
        if (momentum != Momentum.OFF && reveal > 0.5) drawArrows(canvas, endX, endY, trend, dt, nowMs)

        // 9. Badge (momentum-tinted, tailed) — fades in with the reveal.
        if (badge && reveal > 0.02) {
            if (reveal >= 0.999) drawBadge(canvas, endX, endY, w, padR, padT, chartH)
            else {
                val sc = canvas.saveLayerAlpha(0f, 0f, w, h, (255 * reveal).toInt().coerceIn(0, 255))
                drawBadge(canvas, endX, endY, w, padR, padT, chartH)
                canvas.restoreToCount(sc)
            }
        }

        // 10. Value overlay.
        if (showValue) {
            val momentumColor = when (trend) { Trend.UP -> palette.dotUp; Trend.DOWN -> palette.dotDown; else -> palette.dotFlat }
            overlayPaint.color = if (valueMomentumColor) momentumColor.toInt() else palette.tooltipText.toInt()
            canvas.drawText(fmt(displayValue), padL, padT - dp(14f), overlayPaint)
        }

        // 11. Crosshair (scrubbing).
        if (scrubAmount > 0.02) drawCrosshair(canvas, padL, padT, chartH, chartW, leftEdge, rightEdge, endX) { v -> toY(v) }

        // 12. Degen sparks, then unwind the shake transform.
        degenDrawParticles(canvas)
        if (degenShaken) canvas.restore()
    }

    private fun drawArrows(canvas: Canvas, px: Float, py: Float, trend: Trend, dt: Double, nowMs: Double) {
        val upTarget = if (trend == Trend.UP) 1.0 else 0.0
        val downTarget = if (trend == Trend.DOWN) 1.0 else 0.0
        val canUp = arrowDown < 0.02; val canDown = arrowUp < 0.02
        arrowUp = Clock.lerp(arrowUp, if (canUp) upTarget else 0.0, if (upTarget > arrowUp) 0.08 else 0.04, dt).let { if (it < 0.01) 0.0 else if (it > 0.99) 1.0 else it }
        arrowDown = Clock.lerp(arrowDown, if (canDown) downTarget else 0.0, if (downTarget > arrowDown) 0.08 else 0.04, dt).let { if (it < 0.01) 0.0 else if (it > 0.99) 1.0 else it }
        val cycle = (nowMs % 1400.0) / 1400.0
        fun chevrons(dir: Float, opacity: Double) {
            if (opacity < 0.01) return
            val baseX = px + dp(19f)
            for (i in 0 until 2) {
                val localT = cycle - i * 0.2; val dur = 0.35
                val wave = if (localT in 0.0..dur) sin((localT / dur) * PI) else 0.0
                val pulse = 0.3 + 0.7 * wave
                val nudge = if (dir < 0) -dp(3f) else dp(3f)
                val cy = py + dir * (i * dp(8f) - dp(4f)) + nudge
                chevronPaint.color = palette.gridLabel.withAlpha(palette.gridLabel.a * opacity * pulse).toInt()
                val p = Path(); p.moveTo(baseX - dp(5f), cy - dir * dp(3.5f)); p.lineTo(baseX, cy); p.lineTo(baseX + dp(5f), cy - dir * dp(3.5f))
                canvas.drawPath(p, chevronPaint)
            }
        }
        chevrons(-1f, arrowUp); chevrons(1f, arrowDown)
    }

    private fun drawBadge(canvas: Canvas, endX: Float, endY: Float, w: Float, padR: Float, padT: Float, chartH: Float, overrideColor: Int? = null) {
        val label = fmt(displayValue)
        val textW = badgeTextPaint.measureText(label)
        val padX = dp(8f); val padY = dp(4f); val lineH = dp(16f)
        val tailLen = if (badgeVariant == BadgeVariant.MINIMAL || !badgeTail) 0f else dp(7f)
        val pillW = textW + padX * 2; val pillH = lineH + padY * 2
        badgeY = if (badgeY == 0f) endY else Clock.lerp(badgeY.toDouble(), endY.toDouble(), 0.2, frameDt).toFloat()
        badgeY = badgeY.coerceIn(padT + pillH / 2, padT + chartH - pillH / 2)
        val badgeLeft = w - padR + dp(8f) - padX - tailLen
        val badgeTop = badgeY - pillH / 2
        val r = pillH / 2
        val path = Path()
        if (tailLen > 0) {
            val cx = tailLen + pillW - r; val tl = tailLen + r; val spread = dp(3f)
            path.moveTo(badgeLeft + tl, badgeTop)
            path.lineTo(badgeLeft + cx, badgeTop)
            path.arcTo(RectF(badgeLeft + cx - r, badgeTop, badgeLeft + cx + r, badgeTop + pillH), -90f, 180f, false)
            path.lineTo(badgeLeft + tl, badgeTop + pillH)
            path.cubicTo(badgeLeft + tailLen + dp(2f), badgeTop + pillH, badgeLeft + dp(3f), badgeTop + r + spread, badgeLeft, badgeTop + r)
            path.cubicTo(badgeLeft + dp(3f), badgeTop + r - spread, badgeLeft + tailLen + dp(2f), badgeTop, badgeLeft + tl, badgeTop)
            path.close()
        } else path.addRoundRect(RectF(badgeLeft, badgeTop, badgeLeft + pillW, badgeTop + pillH), r, r, Path.Direction.CW)

        val fillColor: Rgba
        if (badgeVariant == BadgeVariant.MINIMAL) { fillColor = palette.badgeOuterBg; badgeTextPaint.color = palette.tooltipText.toInt() }
        else {
            badgeTextPaint.color = palette.badgeText.toInt()
            fillColor = if (momentum == Momentum.OFF || badgeVariant == BadgeVariant.ACCENT) palette.line
            else {
                val g = MomentumDetect.detect(bufferVisibleForBadge()).let { when (it) { Trend.UP -> 1.0; Trend.DOWN -> 0.0; else -> 0.5 } }
                badgeGreen = Clock.lerp(badgeGreen, g, 0.1, frameDt)
                val red = palette.dotDown; val grn = palette.dotUp
                Rgba(red.r + (grn.r - red.r) * badgeGreen, red.g + (grn.g - red.g) * badgeGreen, red.b + (grn.b - red.b) * badgeGreen)
            }
        }
        badgePaint.color = overrideColor ?: fillColor.toInt()
        if (overrideColor != null) badgeTextPaint.color = palette.badgeText.toInt()
        canvas.drawPath(path, badgePaint)
        canvas.drawText(label, badgeLeft + tailLen + padX, badgeY + dp(4.5f), badgeTextPaint)
    }

    private fun bufferVisibleForBadge(): List<LivelinePoint> = if (buffer.size <= 20) buffer else buffer.subList(buffer.size - 20, buffer.size)

    private fun drawReferenceLine(canvas: Canvas, ref: ReferenceLine, padL: Float, padR: Float, padT: Float, w: Float, chartW: Float, chartH: Float, toY: (Double) -> Float) {
        val y = toY(ref.value)
        if (y < padT - dp(10f) || y > padT + chartH + dp(10f)) return
        val label = ref.label
        if (!label.isNullOrEmpty()) {
            refLabelPaint.textSize = dp(11f)
            val tw = refLabelPaint.measureText(label); val cx = padL + chartW / 2; val gap = dp(8f)
            refPaint.color = palette.refLine.toInt()
            canvas.drawLine(padL, y, cx - tw / 2 - gap, y, refPaint)
            canvas.drawLine(cx + tw / 2 + gap, y, w - padR, y, refPaint)
            canvas.drawText(label, cx, y + dp(4f), refLabelPaint)
        } else {
            refDashPaint.color = palette.refLine.toInt()
            canvas.drawLine(padL, y, w - padR, y, refDashPaint)
        }
    }

    private fun drawCrosshair(canvas: Canvas, padL: Float, padT: Float, chartH: Float, chartW: Float, leftEdge: Double, rightEdge: Double, liveDotX: Float, toY: (Double) -> Float) {
        val hx = hoverX.coerceIn(padL, padL + chartW)
        val hoverTime = leftEdge + ((hx - padL) / chartW) * (rightEdge - leftEdge)
        val hoverValue = Interpolate.atTime(buffer, hoverTime) ?: return
        val op = scrubAmount
        crossPaint.color = palette.crosshairLine.withAlpha(palette.crosshairLine.a * op * 0.5).toInt()
        canvas.drawLine(hx, padT, hx, padT + chartH, crossPaint)
        val hy = toY(hoverValue)
        val dr = dp(4f) * min(op * 3, 1.0).toFloat()
        if (dr > dp(0.5f)) { crossDot.color = palette.line.toInt(); canvas.drawCircle(hx, hy, dr, crossDot) }
        if (op < 0.1 || width < 300) return
        val valueText = fmt(hoverValue)
        val timeText = timeFmt("jmmss").format(Date((hoverTime * 1000).toLong()))
        val full = "$valueText  ·  $timeText"
        val totalW = tipPaint.measureText(full)
        var tx = hx - totalW / 2
        tx = tx.coerceIn(padL + dp(4f), liveDotX + dp(7f) - totalW)
        val ty = padT + dp(tooltipY.toFloat())
        val vW = tipPaint.measureText(valueText)
        fun tip(text: String, x: Float, color: Int) {
            if (tooltipOutline) {
                tipPaint.style = Paint.Style.STROKE
                tipPaint.strokeWidth = dp(3.5f)
                tipPaint.strokeJoin = Paint.Join.ROUND
                tipPaint.color = palette.tooltipBg.withAlpha(palette.tooltipBg.a * op).toInt()
                canvas.drawText(text, x, ty, tipPaint)
                tipPaint.style = Paint.Style.FILL
            }
            tipPaint.color = color
            canvas.drawText(text, x, ty, tipPaint)
        }
        tip(valueText, tx, palette.tooltipText.withAlpha(palette.tooltipText.a * op).toInt())
        tip("  ·  $timeText", tx + vW, palette.gridLabel.withAlpha(palette.gridLabel.a * op).toInt())
    }

    // ── Multi-series (ported from Swift drawMultiSeries) ────────────────────────
    private fun drawMultiSeries(canvas: Canvas, w: Float, h: Float, span: Double, now: Double, dt: Double, nowMs: Double) {
        val padL = padLeftOverride?.let { dp(it.toFloat()) } ?: dp(8f)
        val padR = padRightOverride?.let { dp(it.toFloat()) } ?: dp(64f)
        val padT = padTopOverride?.let { dp(it.toFloat()) } ?: dp(12f)
        val padB = padBottomOverride?.let { dp(it.toFloat()) } ?: dp(30f)
        val chartW = w - padL - padR; val chartH = h - padT - padB
        val winBuffer = 0.1
        val rightEdge = now + span * winBuffer; val leftEdge = rightEdge - span

        for (s in series) { val cur = s.buffer.lastOrNull()?.value ?: s.displayValue; s.displayValue = Clock.lerp(s.displayValue, cur, 0.20, dt); s.visAlpha = Clock.lerp(s.visAlpha, if (s.visible) 1.0 else 0.0, 0.18, dt) }

        val values = ArrayList<Double>()
        for (s in series) if (s.visAlpha > 0.01) { for (p in s.buffer) if (p.time in leftEdge..now) values.add(p.value); values.add(s.displayValue) }
        if (values.isEmpty()) return
        domain.update(AutoRange.compute(values, values.last(), null, exaggerate), 0.23, dt, chartH.toDouble())

        msPadL = padL; msPadT = padT; msChartH = chartH; msChartW = chartW; msW = w
        msLeft = leftEdge; msRight = rightEdge; msMax = domain.maxVal; msRange = domain.valRange
        val minV = domain.minVal; val maxV = domain.maxVal; val range = domain.valRange

        // Grid + value labels.
        val pxPerUnit = chartH / range
        gridInterval = Ticks.pickInterval(range, pxPerUnit.toDouble(), dp(36f).toDouble(), gridInterval)
        if (gridInterval > 0) { var g = ceil(minV / gridInterval) * gridInterval; labelPaint.textAlign = Paint.Align.LEFT; while (g <= maxV) { val y = mtoY(g); canvas.drawLine(padL, y, padL + chartW, y, gridPaint); canvas.drawText(fmt(g), padL + chartW + dp(6f), y + dp(4f), labelPaint); g += gridInterval } }
        drawTimeAxis(canvas, w, padL, padR, padT + chartH, leftEdge, rightEdge, span, dt)

        // Non-overlapping endpoint-label y positions.
        val order = series.indices.filter { series[it].visAlpha > 0.01 }.sortedBy { mtoY(series[it].displayValue) }
        var lastY = -Float.MAX_VALUE; val minGap = dp(15f)
        for (idx in order) { var y = mtoY(series[idx].displayValue); if (y - lastY < minGap) y = lastY + minGap; series[idx].labelY = y; lastY = y }

        for (s in series) if (s.visAlpha > 0.01) drawOneSeries(canvas, s, padR, now, s.visAlpha)

        // Left-edge fade — over lines AND time labels (full height), like iOS.
        val fadeW = dp(56f)
        fadePaint.shader = LinearGradient(padL, 0f, padL + fadeW, 0f, palette.background.toInt(), palette.background.withAlpha(0.0).toInt(), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, padL + fadeW, h, fadePaint)

        if (scrubAmount > 0.01) drawMultiSeriesHover(canvas, now, scrubAmount)
    }

    private fun drawOneSeries(canvas: Canvas, s: Series, padR: Float, now: Double, vis: Double = 1.0) {
        val col = s.color.toRgba()
        val endY = mtoY(s.displayValue)
        dashPaint.color = col.withAlpha(0.35 * vis).toInt()
        canvas.drawLine(msPadL, endY, msPadL + msChartW, endY, dashPaint)

        val pts = ArrayList<Point>()
        for (p in s.buffer) { if (p.time < msLeft - 2) continue; if (p.time > now) break; pts.add(Point(mtoX(p.time).toDouble(), mtoY(p.value).toDouble())) }
        if (pts.isEmpty()) return
        pts[pts.size - 1] = Point(pts.last().x, endY.toDouble())
        val dotX = pts.last().x.toFloat()
        if (pts.size >= 2) {
            val path = Path(); path.moveTo(pts[0].x.toFloat(), pts[0].y.toFloat())
            for (seg in PathBuilder.monotoneSegments(pts)) path.cubicTo(seg.control1.x.toFloat(), seg.control1.y.toFloat(), seg.control2.x.toFloat(), seg.control2.y.toFloat(), seg.end.x.toFloat(), seg.end.y.toFloat())
            linePaint.color = col.withAlpha(col.a * vis).toInt(); linePaint.strokeWidth = dp(lineWidth.toFloat())
            canvas.drawPath(path, linePaint)
        }
        dotOuter.alpha = (255 * vis).toInt().coerceIn(0, 255); canvas.drawCircle(dotX, endY, dp(6.5f), dotOuter)
        dotInner.color = col.withAlpha(col.a * vis).toInt(); canvas.drawCircle(dotX, endY, dp(3.5f), dotInner)
        if (!s.label.isNullOrEmpty()) { seriesLabelPaint.color = col.withAlpha(col.a * vis).toInt(); canvas.drawText(s.label, dotX + dp(10f), s.labelY + dp(4.5f), seriesLabelPaint) }
    }

    private fun drawMultiSeriesHover(canvas: Canvas, now: Double, opacity: Double) {
        val maxX = mtoX(now)
        val hx = hoverX.coerceIn(msPadL, maxX)
        val t = msLeft + ((hx - msPadL) / msChartW).toDouble() * (msRight - msLeft)
        crossPaint.color = palette.crosshairLine.withAlpha(palette.crosshairLine.a * opacity * 0.5).toInt()
        canvas.drawLine(hx, msPadT, hx, msPadT + msChartH, crossPaint)

        tipPaint.textAlign = Paint.Align.LEFT
        val segs = ArrayList<Pair<String, Int>>()
        segs.add(Pair(timeFmt("jmmss").format(Date((t * 1000).toLong())), palette.gridLabel.toInt()))
        for (s in series) if (s.visible) {
            val v = Interpolate.atTime(s.buffer, t) ?: continue
            crossDot.color = s.color.toRgba().withAlpha(opacity).toInt()
            canvas.drawCircle(hx, mtoY(v), dp(4f), crossDot)
            segs.add(Pair("  " + (s.label ?: s.id) + " ", palette.gridLabel.toInt()))
            segs.add(Pair(fmt(v), s.color))
        }
        val widths = segs.map { tipPaint.measureText(it.first) }
        val total = widths.sum()
        var tx = (hx - total / 2).coerceIn(msPadL + dp(4f), msW - dp(12f) - total)
        val ty = msPadT + dp(24f)
        for ((i, seg) in segs.withIndex()) {
            tipPaint.color = (if (seg.second == palette.gridLabel.toInt()) palette.gridLabel.withAlpha(palette.gridLabel.a * opacity).toInt() else seg.second.toRgba().withAlpha(opacity).toInt())
            canvas.drawText(seg.first, tx, ty, tipPaint)
            tx += widths[i]
        }
    }

    // ── Orderbook stream (ported from Swift LivelineView+Orderbook) ─────────────
    private fun drawOrderbook(canvas: Canvas, padL: Float, padT: Float, chartH: Float, momentumMag: Double, groupAlpha: Double, dt: Double) {
        val book = orderbook ?: return
        if (book.bids.isEmpty() && book.asks.isEmpty()) return
        val dtSec = dt / 1000
        val activity = min(1.0, max(0.0, momentumMag * 0.5 + orderbookChurn * 0.8))
        if (dtSec > 0) {
            obSpawnClock += dtSec
            val interval = 0.26 - 0.16 * activity
            var guard = 0
            while (obSpawnClock >= interval && guard < 4) { obSpawnClock -= interval; guard++; emitOrderbook(book, padL, padT, chartH) }
        }
        if (obLabels.isEmpty()) return
        val travel = chartH + dp(24f)
        val step = ((60.0 + 90.0 * activity) * dtSec).toFloat()
        for (l in obLabels) l.yOffset += step
        obLabels.removeAll { it.yOffset >= travel }
        for (l in obLabels) {
            val progress = (l.yOffset / travel).toDouble()
            val fadeIn = min(1.0, progress / 0.08); val fadeOut = 1 - max(0.0, (progress - 0.7) / 0.3)
            val alpha = max(0.0, min(1.0, fadeIn * fadeOut)) * (0.28 + 0.5 * l.weight) * groupAlpha
            if (alpha < 0.01) continue
            obPaint.color = (if (l.isBid) bull else bear).withAlpha(alpha).toInt()
            canvas.drawText(l.text, l.x, l.spawnY - l.yOffset, obPaint)
        }
    }

    private fun emitOrderbook(book: OrderbookData, padL: Float, padT: Float, chartH: Float) {
        val preferBid = Math.random() < 0.5
        val isBid = (preferBid && book.bids.isNotEmpty()) || book.asks.isEmpty()
        val levels = if (isBid) book.bids else book.asks
        val top = levels.take(8)
        val pick = if (top.isEmpty()) return else top[(Math.random() * top.size).toInt().coerceAtMost(top.size - 1)]
        val maxSize = top.maxOf { it.size }
        val weight = if (maxSize > 0) min(1.0, pick.size / maxSize) else 0.5
        // Keep a minimum vertical gap between rising labels so the column reads as
        // a spaced stream rather than a solid block (the newest label sits last).
        obLabels.lastOrNull()?.let { if (it.yOffset < dp(20f)) return }
        obLabels.add(ObLabel("+$" + fmtSize(pick.size), padL + dp(6f), padT + chartH - dp(6f), isBid, weight))
        if (obLabels.size > 40) obLabels.removeAt(0)
    }

    private fun fmtSize(s: Double): String = when {
        s >= 1_000_000 -> String.format("%.1fM", s / 1_000_000)
        s >= 1_000 -> String.format("%.1fk", s / 1_000)
        s >= 10 -> String.format("%.0f", s)
        else -> String.format("%.1f", s)
    }

    // ── Degen (shake + sparks) ──────────────────────────────────────────────────
    /** Decays the shake and advances particles (no canvas ops). */
    private fun degenAdvance(dt: Double) {
        if (!degen) { if (degenParticles.isNotEmpty()) degenParticles.clear(); degenShake = 0.0; return }
        degenShake *= Math.pow(0.86, dt / Clock.FRAME_MS)
        if (degenShake < 0.2) degenShake = 0.0
        val step = dt / 1000
        for (p in degenParticles) { p.vy += 900 * step; p.x += p.vx * step; p.y += p.vy * step; p.life -= step }
        degenParticles.removeAll { it.life <= 0 }
    }

    /** Fires a burst when the value pops above its slowly-trailing baseline. */
    private fun degenTrigger(dotX: Float, dotY: Float, value: Double, range: Double, dt: Double) {
        if (!degen) return
        if (!degenBaselineInit) { degenBaseline = value; degenBaselineInit = true }
        degenBaseline += (value - degenBaseline) * min(1.0, 0.035 * dt / Clock.FRAME_MS)
        val rise = if (range > 0) (value - degenBaseline) / range else 0.0
        if (rise > 0.06 && degenArmed) {
            degenArmed = false
            if (haptics) performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
            repeat(18) {
                val angle = -PI * Math.random()
                val speed = 120 + Math.random() * 220
                val life = 0.5 + Math.random() * 0.45
                degenParticles.add(DegenParticle(dotX.toDouble(), dotY.toDouble(), cos(angle) * speed, sin(angle) * speed, life, life))
            }
            if (degenParticles.size > 200) while (degenParticles.size > 200) degenParticles.removeAt(0)
            degenShake = 7.0
        } else if (rise < 0.02) degenArmed = true
    }

    private fun degenDrawParticles(canvas: Canvas) {
        if (!degen || degenParticles.isEmpty()) return
        val spark = palette.line
        for (p in degenParticles) {
            val t = max(0.0, p.life / p.maxLife)
            val r = (linePaint.strokeWidth * (0.4 + 0.5 * t)).toFloat()
            sparkPaint.color = spark.withAlpha(t * 0.9).toInt()
            canvas.drawCircle(p.x.toFloat(), p.y.toFloat(), r, sparkPaint)
        }
    }

    // ── Candle mode ─────────────────────────────────────────────────────────────
    private fun drawCandleFrame(canvas: Canvas, w: Float, padL: Float, padR: Float, padT: Float, chartH: Float, span: Double, now: Double, leftEdge: Double, rightEdge: Double, nowMs: Double, dt: Double, grow: Double = 1.0) {
        val liveT = liveCandle?.time
        liveCandle?.let { liveBull = Clock.lerp(liveBull, if (it.close >= it.open) 1.0 else 0.0, 0.12, dt) }
        val all = ArrayList(candles)
        liveCandle?.let { lc -> if (all.none { it.time == lc.time }) all.add(lc) }
        val visible = all.filter { it.time + candleWidth >= leftEdge && it.time <= rightEdge }.sortedBy { it.time }
        if (visible.isEmpty()) return

        domain.update(AutoRange.computeCandles(visible), 0.15, dt, chartH.toDouble())
        val minV = domain.minVal; val maxV = domain.maxVal; val range = domain.valRange
        val chartW = w - padL - padR
        fun toX(t: Double) = padL + ((t - leftEdge) / (rightEdge - leftEdge)).toFloat() * chartW
        fun toY(v: Double) = padT + ((maxV - v) / range).toFloat() * chartH

        // Grid + value labels.
        val pxPerUnit = chartH / range
        gridInterval = Ticks.pickInterval(range, pxPerUnit.toDouble(), dp(36f).toDouble(), gridInterval)
        if (grid && gridInterval > 0) {
            var g = ceil(minV / gridInterval) * gridInterval
            labelPaint.textAlign = Paint.Align.LEFT
            while (g <= maxV) { val y = toY(g); canvas.drawLine(padL, y, padL + chartW, y, gridPaint); canvas.drawText(fmt(g), padL + chartW + dp(6f), y + dp(4f), labelPaint); g += gridInterval }
        }

        // Candlesticks. During a mode morph (grow < 1) each candle collapses
        // toward its close, so it melts into the line overlay drawn below.
        val growF = grow.toFloat().coerceIn(0f, 1f)
        val pxPerSec = chartW / span.toFloat()
        val bodyW = max(1f, candleWidth.toFloat() * pxPerSec * 0.7f)
        val wickW = max(0.8f, min(2f, bodyW * 0.15f))
        val radius = if (bodyW > 6) dp(1.5f) else 0f
        val half = bodyW / 2
        val livePulse = 0.12 + sin(nowMs * 0.004) * 0.08
        for (c in visible) {
            val cx = toX(c.time + candleWidth / 2)
            val isLive = liveT != null && c.time == liveT
            val color = if (isLive) blend(bear, bull, liveBull) else if (c.close >= c.open) bull else bear
            val closeY = toY(c.close)
            fun grown(y: Float) = if (growF >= 1f) y else closeY + (y - closeY) * growF
            val bodyTop = grown(toY(max(c.open, c.close))); val bodyBottom = grown(toY(min(c.open, c.close)))
            val bodyH = max(1f, bodyBottom - bodyTop)
            candleStroke.color = color.withAlpha(color.a * growF).toInt(); candleStroke.strokeWidth = wickW
            if (bodyTop - grown(toY(c.high)) > 0.5f) canvas.drawLine(cx, bodyTop, cx, grown(toY(c.high)), candleStroke)
            if (grown(toY(c.low)) - bodyBottom > 0.5f) canvas.drawLine(cx, bodyBottom, cx, grown(toY(c.low)), candleStroke)
            candleFill.color = color.withAlpha(color.a * growF).toInt()
            val rect = RectF(cx - half, bodyTop, cx + half, bodyTop + bodyH)
            if (radius > 0 && bodyH >= radius * 2) canvas.drawRoundRect(rect, radius, radius, candleFill) else canvas.drawRect(rect, candleFill)
            if (isLive) { candleFill.color = color.withAlpha(color.a * livePulse * growF).toInt(); if (radius > 0 && bodyH >= radius * 2) canvas.drawRoundRect(rect, radius, radius, candleFill) else canvas.drawRect(rect, candleFill) }
        }

        // Line overlay: fades in from the `data` buffer as the candles collapse.
        if (growF < 1f) {
            val a = (1f - growF).toDouble()
            linePaint.color = palette.line.withAlpha(palette.line.a * a).toInt()
            linePaint.strokeWidth = dp(lineWidth.toFloat())
            val pts = ArrayList<Point>()
            for (p in buffer) { if (p.time < leftEdge - 2) continue; if (p.time > now) break; pts.add(Point(toX(p.time).toDouble(), toY(p.value).toDouble())) }
            if (pts.size >= 2) {
                val path = Path(); path.moveTo(pts[0].x.toFloat(), pts[0].y.toFloat())
                for (s in PathBuilder.monotoneSegments(pts)) path.cubicTo(s.control1.x.toFloat(), s.control1.y.toFloat(), s.control2.x.toFloat(), s.control2.y.toFloat(), s.end.x.toFloat(), s.end.y.toFloat())
                canvas.drawPath(path, linePaint)
            }
        }

        drawTimeAxis(canvas, w, padL, padR, padT + chartH, leftEdge, rightEdge, span, dt)

        // Left-edge fade over candles + time labels.
        val fadeW = dp(56f)
        fadePaint.shader = LinearGradient(padL, 0f, padL + fadeW, 0f, palette.background.toInt(), palette.background.withAlpha(0.0).toInt(), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, padL + fadeW, padT + chartH + dp(32f), fadePaint)

        // Live close dot + badge (tinted by the live candle direction).
        val liveClose = liveCandle?.close ?: visible.last().close
        if (displayValue == 0.0) displayValue = liveClose
        value = liveClose
        val speed = Domain.adaptiveSpeed(value, displayValue, minV, maxV, 0.25)
        displayValue = Clock.lerp(displayValue, liveClose, speed, dt)
        val endX = toX(now); val endY = toY(displayValue).coerceIn(padT, padT + chartH)
        val col = if ((liveCandle?.let { it.close >= it.open } ?: true)) bull else bear
        drawBadge(canvas, endX, endY, w, padR, padT, chartH, col.toInt())
    }

    // ── Time axis ─────────────────────────────────────────────────────────────
    private class TimeLabel(var alpha: Double, var text: String)
    private val timeAlphas = HashMap<Long, TimeLabel>()
    private val timePatterns = HashMap<String, SimpleDateFormat>()
    private fun timeFmt(template: String) = timePatterns.getOrPut(template) { SimpleDateFormat(DateFormat.getBestDateTimePattern(Locale.getDefault(), template), Locale.getDefault()) }
    private fun axisTimeLabel(t: Double, interval: Double): String {
        val template = when { interval >= 31_536_000 -> "yyyy"; interval >= 2_592_000 -> "MMMyyyy"; interval >= 86_400 -> "dMMM"; interval >= 60 -> "jmm"; else -> "jmmss" }
        return timeFmt(template).format(Date((t * 1000).toLong()))
    }
    private fun drawTimeAxis(canvas: Canvas, w: Float, padL: Float, padR: Float, lineY: Float, leftEdge: Double, rightEdge: Double, span: Double, dt: Double) {
        val chartLeft = padL; val chartRight = w - padR; val chartW = chartRight - chartLeft
        val tickLen = dp(5f); val fadeZone = dp(50f)
        fun toX(t: Double) = chartLeft + ((t - leftEdge) / (rightEdge - leftEdge)).toFloat() * chartW
        // Fade the whole label uniformly near BOTH edges so it dissolves in place
        // instead of a tail bleeding past the edge. The left needs alpha (not just
        // the gradient) because a centred label's right half can extend beyond the
        // gradient's fade zone and stay visible; fading the label's alpha takes the
        // entire label — tail included — down together.
        fun edgeAlpha(x: Float): Double {
            val fromRight = chartRight - x
            val fromLeft = x - chartLeft
            val r = when { fromRight >= fadeZone -> 1.0; fromRight <= 0f -> 0.0; else -> (fromRight / fadeZone).toDouble() }
            val l = when { fromLeft >= fadeZone -> 1.0; fromLeft <= 0f -> 0.0; else -> (fromLeft / fadeZone).toDouble() }
            return min(r, l)
        }
        val targetPxPerSec = chartW / span
        var interval = Intervals.niceTimeInterval(span)
        // Widen the interval until adjacent labels can't overlap (measure a
        // representative label), so the visible set never swaps as it scrolls.
        var guard = 0
        while (guard++ < 8 && interval < span) {
            val sampleW = timeLabelPaint.measureText(axisTimeLabel(rightEdge, interval)) + dp(24f)
            if (interval * targetPxPerSec >= sampleW) break
            interval *= 2
        }
        val firstTime = ceil((leftEdge - interval) / interval) * interval
        val targetKeys = HashSet<Long>(); var t = firstTime
        while (t <= rightEdge + interval && targetKeys.size < 30) { targetKeys.add(Math.round(t * 100)); t += interval }
        for (key in targetKeys) { val text = axisTimeLabel(key / 100.0, interval); val e = timeAlphas[key]; if (e == null) timeAlphas[key] = TimeLabel(0.0, text) else e.text = text }
        val remove = ArrayList<Long>()
        // `label.alpha` is presence (eased appear/disappear); the geometric edge
        // fade is applied directly at draw time so it never lags.
        for ((key, label) in timeAlphas) { val target = if (targetKeys.contains(key)) 1.0 else 0.0; var next = Clock.lerp(label.alpha, target, 0.08, dt); if (abs(next - target) < 0.02) next = target; if (next < 0.01 && target == 0.0) remove.add(key) else label.alpha = next }
        for (k in remove) timeAlphas.remove(k)
        axisPaint.alpha = (palette.gridLine.a * 255).toInt(); canvas.drawLine(chartLeft, lineY, chartRight, lineY, axisPaint)
        class L(val x: Float, val alpha: Double, val text: String, val wpx: Float)
        val list = ArrayList<L>()
        // Draw a label as long as it has any alpha; only cull ones that have
        // scrolled well off an edge (so they fade out rather than pop).
        for ((key, label) in timeAlphas) { if (label.alpha < 0.02) continue; val x = toX(key / 100.0); if (x < chartLeft - dp(90f) || x > chartRight + dp(20f)) continue; val a = label.alpha * edgeAlpha(x); if (a < 0.01) continue; list.add(L(x, a, label.text, timeLabelPaint.measureText(label.text))) }
        list.sortBy { it.x }
        val drawn = ArrayList<L>()
        for (label in list) { val prev = drawn.lastOrNull(); if (prev != null && label.x - label.wpx / 2 < prev.x + prev.wpx / 2 + dp(8f)) { if (label.alpha > prev.alpha) drawn[drawn.size - 1] = label; continue }; drawn.add(label) }
        val baseAxisA = palette.gridLine.a; val baseLabelA = palette.timeLabel.a
        for (label in drawn) {
            axisPaint.alpha = (baseAxisA * label.alpha * 255).toInt().coerceIn(0, 255); canvas.drawLine(label.x, lineY, label.x, lineY + tickLen, axisPaint)
            timeLabelPaint.alpha = (baseLabelA * label.alpha * 255).toInt().coerceIn(0, 255); canvas.drawText(label.text, label.x, lineY + tickLen + dp(12f), timeLabelPaint)
        }
    }
}

private fun Rgba.toInt(): Int = Color.argb((a * 255).toInt().coerceIn(0, 255), (r * 255).toInt().coerceIn(0, 255), (g * 255).toInt().coerceIn(0, 255), (b * 255).toInt().coerceIn(0, 255))
private fun Int.toRgba(): Rgba = Rgba(Color.red(this) / 255.0, Color.green(this) / 255.0, Color.blue(this) / 255.0, Color.alpha(this) / 255.0)
