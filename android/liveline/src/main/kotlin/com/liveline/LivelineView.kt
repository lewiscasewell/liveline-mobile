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
import com.liveline.core.LivelinePoint
import com.liveline.core.LivelineTheme
import com.liveline.core.Momentum
import com.liveline.core.MomentumDetect
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
    var showValue: Boolean = false
    var valueMomentumColor: Boolean = false
    var fill: Boolean = true
    var exaggerate: Boolean = false
    var loading: Boolean = false
    var paused: Boolean = false
    var scrub: Boolean = true
    var referenceLine: ReferenceLine? = null
    var valuePrefix: String = ""
    var valueSuffix: String = ""
    var valueDecimals: Int = 2

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

    private fun rebuildPalette() {
        palette = Theme.palette(accent.toRgba(), theme)
        linePaint.color = palette.line.toInt(); linePaint.strokeWidth = dp(palette.lineWidth.toFloat())
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

    private fun fmt(v: Double): String = valuePrefix + String.format("%.${valueDecimals}f", v) + valueSuffix

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
        val nowMs = System.nanoTime() / 1_000_000.0
        val dt = frameDt
        advanceWindow(nowMs)
        val span = displayWindow

        loadingAlpha = Clock.lerp(loadingAlpha, if (loading) 1.0 else 0.0, 0.1, dt).coerceIn(0.0, 1.0)
        scrubAmount = Clock.lerp(scrubAmount, if (scrubbing) 1.0 else 0.0, 0.2, dt).coerceIn(0.0, 1.0)

        val padL = dp(8f); val padR = dp(64f); val padT = if (showValue) dp(40f) else dp(12f); val padB = dp(30f)
        val chartW = w - padL - padR; val chartH = h - padT - padB
        if (buffer.size < 2) return

        // Freeze `now` while paused so the line stops scrolling.
        val realNow = System.currentTimeMillis() / 1000.0
        if (!paused) pauseNow = realNow
        val now = if (paused) pauseNow else realNow
        val rightEdge = now + span * 0.05
        val leftEdge = rightEdge - span

        var startIdx = 0
        for (i in buffer.indices) if (buffer[i].time >= leftEdge) { startIdx = max(0, i - 1); break }
        val visible = ArrayList<LivelinePoint>()
        for (i in startIdx until buffer.size) if (buffer[i].time <= now) visible.add(buffer[i])
        if (visible.size < 2) return

        val speed = Domain.adaptiveSpeed(value, displayValue, domain.minVal, domain.maxVal, 0.08)
        displayValue = Clock.lerp(displayValue, value, speed, dt)
        val target = AutoRange.compute(visible.map { it.value }, displayValue, referenceLine?.value, exaggerate)
        domain.update(target, speed, dt, chartH.toDouble())
        val minV = domain.minVal; val maxV = domain.maxVal; val range = domain.valRange
        fun toX(t: Double) = padL + ((t - leftEdge) / (rightEdge - leftEdge)).toFloat() * chartW
        fun toY(v: Double) = padT + ((maxV - v) / range).toFloat() * chartH

        // 1. Reference line.
        referenceLine?.let { drawReferenceLine(canvas, it, padL, padR, padT, w, chartW, chartH) { v -> toY(v) } }

        // 2. Grid + value labels.
        val pxPerUnit = chartH / range
        gridInterval = Ticks.pickInterval(range, pxPerUnit.toDouble(), dp(36f).toDouble(), gridInterval)
        if (gridInterval > 0) {
            var g = ceil(minV / gridInterval) * gridInterval
            labelPaint.textAlign = Paint.Align.LEFT
            while (g <= maxV) {
                val y = toY(g)
                canvas.drawLine(padL, y, padL + chartW, y, gridPaint)
                canvas.drawText(String.format("%.${valueDecimals}f", g), padL + chartW + dp(6f), y + dp(4f), labelPaint)
                g += gridInterval
            }
        }

        val trend = if (momentum == Momentum.OFF) Trend.FLAT else when (momentum) {
            Momentum.UP -> Trend.UP; Momentum.DOWN -> Trend.DOWN; Momentum.FLAT -> Trend.FLAT
            else -> MomentumDetect.detect(visible)
        }
        val dotColor = when (trend) { Trend.UP -> palette.dotUp; Trend.DOWN -> palette.dotDown; else -> palette.dotFlat }

        val endX = toX(now); val endY = toY(displayValue)
        val pts = ArrayList<Point>(visible.size)
        for (p in visible) pts.add(Point(toX(p.time).toDouble(), toY(p.value).toDouble()))
        pts[pts.size - 1] = Point(endX.toDouble(), endY.toDouble())

        // 3. Dashed baseline.
        dashPaint.color = palette.dashLine.toInt()
        canvas.drawLine(padL, endY, endX, endY, dashPaint)

        // 4. Line + fill.
        val path = Path()
        path.moveTo(pts[0].x.toFloat(), pts[0].y.toFloat())
        for (s in PathBuilder.monotoneSegments(pts)) path.cubicTo(s.control1.x.toFloat(), s.control1.y.toFloat(), s.control2.x.toFloat(), s.control2.y.toFloat(), s.end.x.toFloat(), s.end.y.toFloat())
        if (fill) {
            val f = Path(path); f.lineTo(pts.last().x.toFloat(), padT + chartH); f.lineTo(pts.first().x.toFloat(), padT + chartH); f.close()
            fillPaint.shader = LinearGradient(0f, padT, 0f, padT + chartH, palette.fillTop.toInt(), palette.fillBottom.toInt(), Shader.TileMode.CLAMP)
            canvas.drawPath(f, fillPaint)
        }
        canvas.drawPath(path, linePaint)

        // 4b. While scrubbing, fade the line to the RIGHT of the crosshair.
        if (scrubAmount > 0.02) {
            val hx = hoverX.coerceIn(padL, padL + chartW)
            scrubFadePaint.color = palette.background.withAlpha(palette.background.a * scrubAmount * 0.55).toInt()
            canvas.drawRect(hx, padT, padL + chartW, padT + chartH, scrubFadePaint)
        }

        // 5. Left-edge fade.
        val fadeW = dp(56f)
        fadePaint.shader = LinearGradient(padL, 0f, padL + fadeW, 0f, palette.background.toInt(), palette.background.withAlpha(0.0).toInt(), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, padT, padL + fadeW, padT + chartH, fadePaint)

        // 6. Time axis.
        drawTimeAxis(canvas, w, padL, padR, padT + chartH, leftEdge, rightEdge, span, dt)

        // 7. Live dot + pulse (dimmed + line-coloured — no red/green — while scrubbing).
        val dim = scrubAmount * 0.7
        val headColor = if (scrubAmount > 0.1) palette.line else dotColor
        if (dim < 0.3) {
            val t = (nowMs % 1500.0) / 900.0
            if (t < 1) { ringPaint.color = headColor.withAlpha(headColor.a * 0.35 * (1 - t) * (1 - dim * 3)).toInt(); canvas.drawCircle(endX, endY, dp(9f) + (t * dp(12f).toDouble()).toFloat(), ringPaint) }
        }
        val dotA = (1 - dim)
        dotOuter.alpha = (255 * dotA).toInt().coerceIn(0, 255)
        canvas.drawCircle(endX, endY, dp(6.5f), dotOuter)
        dotInner.color = headColor.withAlpha(headColor.a * dotA).toInt()
        canvas.drawCircle(endX, endY, dp(3.5f), dotInner)

        // 8. Momentum arrows.
        if (momentum != Momentum.OFF) drawArrows(canvas, endX, endY, trend, dt, nowMs)

        // 9. Badge (momentum-tinted, tailed).
        drawBadge(canvas, endX, endY, w, padR, padT, chartH)

        // 10. Value overlay.
        if (showValue) {
            overlayPaint.color = if (valueMomentumColor) dotColor.toInt() else palette.tooltipText.toInt()
            canvas.drawText(fmt(displayValue), padL, padT - dp(14f), overlayPaint)
        }

        // 11. Crosshair (scrubbing).
        if (scrubAmount > 0.02) drawCrosshair(canvas, padL, padT, chartH, chartW, leftEdge, rightEdge, endX) { v -> toY(v) }
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

    private fun drawBadge(canvas: Canvas, endX: Float, endY: Float, w: Float, padR: Float, padT: Float, chartH: Float) {
        val label = fmt(displayValue)
        val textW = badgeTextPaint.measureText(label)
        val padX = dp(8f); val padY = dp(4f); val lineH = dp(16f)
        val tailLen = if (badgeVariant == BadgeVariant.MINIMAL) 0f else dp(7f)
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
        badgePaint.color = fillColor.toInt()
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
        tipPaint.color = palette.tooltipText.withAlpha(palette.tooltipText.a * op).toInt()
        val full = "$valueText  ·  $timeText"
        val totalW = tipPaint.measureText(full)
        var tx = hx - totalW / 2
        tx = tx.coerceIn(padL + dp(4f), liveDotX + dp(7f) - totalW)
        val ty = padT + dp(24f)
        canvas.drawText(valueText, tx, ty, tipPaint)
        val vW = tipPaint.measureText(valueText)
        val save = tipPaint.color
        tipPaint.color = palette.gridLabel.withAlpha(palette.gridLabel.a * op).toInt()
        canvas.drawText("  ·  $timeText", tx + vW, ty, tipPaint)
        tipPaint.color = save
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
        fun edgeAlpha(x: Float): Double { val fromEdge = min(x - chartLeft, chartRight - x); return when { fromEdge >= fadeZone -> 1.0; fromEdge <= 0f -> 0.0; else -> (fromEdge / fadeZone).toDouble() } }
        val targetPxPerSec = chartW / span
        var interval = Intervals.niceTimeInterval(span)
        while (interval * targetPxPerSec < 60 && interval < span) interval *= 2
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
