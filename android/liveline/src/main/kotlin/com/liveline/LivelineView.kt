package com.liveline

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.graphics.Typeface
import android.text.format.DateFormat
import android.util.AttributeSet
import android.view.Choreographer
import android.view.View
import com.liveline.core.AutoRange
import com.liveline.core.Clock
import com.liveline.core.Domain
import com.liveline.core.Intervals
import com.liveline.core.LivelinePoint
import com.liveline.core.LivelineTheme
import com.liveline.core.MomentumDetect
import com.liveline.core.PathBuilder
import com.liveline.core.Point
import com.liveline.core.Rgba
import com.liveline.core.Theme
import com.liveline.core.Ticks
import com.liveline.core.Trend
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

/**
 * The Android line-mode renderer for liveline — a faithful port of the Swift
 * `LivelineView` draw pipeline onto a `Canvas`. All maths (range, easing,
 * spline, momentum, ticks) and colours (palette) come from `com.liveline.core`;
 * this class maps to pixels and paints in the same draw order as iOS.
 *
 * Feed it a backfill with [setData] and live samples with [push]; the render
 * loop (a `Choreographer` frame callback) eases + scrolls at the display rate.
 */
class LivelineView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs), Choreographer.FrameCallback {

    // ── Public API ──────────────────────────────────────────────────────────
    /** Accent colour (ARGB int); the palette derives from it. */
    var accent: Int = Color.parseColor("#3b82f6")
        set(v) { field = v; rebuildPalette() }
    /** Base tone. */
    var theme: LivelineTheme = LivelineTheme.DARK
        set(v) { field = v; rebuildPalette() }
    /** Visible span in seconds. */
    var windowSeconds: Double = 30.0

    /** Replaces the backfill history. */
    fun setData(points: List<LivelinePoint>) {
        buffer.clear()
        buffer.addAll(points)
        points.lastOrNull()?.let { value = it.value; displayValue = it.value }
        lastCommitSec = points.lastOrNull()?.time ?: 0.0
        invalidate()
    }

    /** Appends one live sample, bucketed to the window resolution. */
    fun push(point: LivelinePoint) {
        value = point.value
        val bucket = windowSeconds / 300.0
        if (buffer.isEmpty() || point.time - lastCommitSec >= bucket) {
            buffer.add(point)
            lastCommitSec = point.time
            if (buffer.size > 8192) buffer.removeAt(0)
        } else {
            buffer[buffer.size - 1] = point
        }
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

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d

    private var palette = Theme.palette(accent.toRgba(), theme)

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1f) }
    private val dashPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = dp(1f)
        pathEffect = DashPathEffect(floatArrayOf(dp(3f), dp(3f)), 0f)
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(11f); typeface = Typeface.MONOSPACE }
    private val timeLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = dp(11f); typeface = Typeface.MONOSPACE; textAlign = Paint.Align.CENTER
    }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1f) }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = dp(1.5f) }
    private val dotOuter = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; color = Color.WHITE }
    private val dotInner = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val badgeText = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = dp(13f); typeface = Typeface.MONOSPACE }
    private val fadePaint = Paint().apply { style = Paint.Style.FILL }

    private fun rebuildPalette() {
        palette = Theme.palette(accent.toRgba(), theme)
        linePaint.color = palette.line.toInt()
        linePaint.strokeWidth = dp(palette.lineWidth.toFloat())
        gridPaint.color = palette.gridLine.toInt()
        axisPaint.color = palette.gridLine.toInt()
        labelPaint.color = palette.gridLabel.toInt()
        timeLabelPaint.color = palette.timeLabel.toInt()
        badgeText.color = palette.badgeText.toInt()
        dotOuter.color = palette.badgeOuterBg.toInt()
        invalidate()
    }

    init { rebuildPalette() }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        val nowMs = frameTimeNanos / 1_000_000.0
        frameDt = if (lastFrameMs == 0.0) Clock.FRAME_MS else (nowMs - lastFrameMs).coerceIn(1.0, 64.0)
        lastFrameMs = nowMs
        invalidate()
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0 || buffer.size < 2) return

        val nowMs = System.nanoTime() / 1_000_000.0
        val padL = dp(8f); val padR = dp(64f); val padT = dp(12f); val padB = dp(30f)
        val chartW = w - padL - padR
        val chartH = h - padT - padB

        val now = System.currentTimeMillis() / 1000.0
        val rightEdge = now + windowSeconds * 0.05
        val leftEdge = rightEdge - windowSeconds

        var startIdx = 0
        for (i in buffer.indices) {
            if (buffer[i].time >= leftEdge) { startIdx = max(0, i - 1); break }
        }
        val visible = ArrayList<LivelinePoint>()
        for (i in startIdx until buffer.size) if (buffer[i].time <= now) visible.add(buffer[i])
        if (visible.size < 2) return

        val speed = Domain.adaptiveSpeed(value, displayValue, domain.minVal, domain.maxVal, 0.08)
        displayValue = Clock.lerp(displayValue, value, speed, frameDt)
        val target = AutoRange.compute(visible.map { it.value }, displayValue)
        domain.update(target, speed, frameDt, chartH.toDouble())

        val minV = domain.minVal; val maxV = domain.maxVal; val range = domain.valRange
        fun toX(t: Double) = padL + ((t - leftEdge) / (rightEdge - leftEdge)).toFloat() * chartW
        fun toY(v: Double) = padT + ((maxV - v) / range).toFloat() * chartH

        // 1. Grid + right-edge value labels.
        val pxPerUnit = chartH / range
        gridInterval = Ticks.pickInterval(range, pxPerUnit.toDouble(), dp(36f).toDouble(), gridInterval)
        if (gridInterval > 0) {
            var g = ceil(minV / gridInterval) * gridInterval
            labelPaint.textAlign = Paint.Align.LEFT
            while (g <= maxV) {
                val y = toY(g)
                canvas.drawLine(padL, y, padL + chartW, y, gridPaint)
                canvas.drawText(fmt(g), padL + chartW + dp(6f), y + dp(4f), labelPaint)
                g += gridInterval
            }
        }

        // Head rides at `now` with the eased value (smooth extension).
        val endX = toX(now); val endY = toY(displayValue)
        val pts = ArrayList<Point>(visible.size)
        for (p in visible) pts.add(Point(toX(p.time).toDouble(), toY(p.value).toDouble()))
        pts[pts.size - 1] = Point(endX.toDouble(), endY.toDouble())

        // 2. Momentum-coloured dot.
        val trend = MomentumDetect.detect(visible)
        val dotColor = when (trend) {
            Trend.UP -> palette.dotUp; Trend.DOWN -> palette.dotDown; else -> palette.dotFlat
        }

        // 3. Dashed current-value baseline.
        dashPaint.color = palette.dashLine.toInt()
        canvas.drawLine(padL, endY, endX, endY, dashPaint)

        // 4. Line + area fill (spline via the shared Fritsch–Carlson builder).
        val path = Path()
        path.moveTo(pts[0].x.toFloat(), pts[0].y.toFloat())
        for (s in PathBuilder.monotoneSegments(pts)) {
            path.cubicTo(
                s.control1.x.toFloat(), s.control1.y.toFloat(),
                s.control2.x.toFloat(), s.control2.y.toFloat(),
                s.end.x.toFloat(), s.end.y.toFloat(),
            )
        }
        val fill = Path(path)
        fill.lineTo(pts.last().x.toFloat(), padT + chartH)
        fill.lineTo(pts.first().x.toFloat(), padT + chartH)
        fill.close()
        fillPaint.shader = LinearGradient(
            0f, padT, 0f, padT + chartH, palette.fillTop.toInt(), palette.fillBottom.toInt(), Shader.TileMode.CLAMP,
        )
        canvas.drawPath(fill, fillPaint)
        canvas.drawPath(path, linePaint)

        // 5. Left-edge fade into the background.
        val fadeW = dp(56f)
        fadePaint.shader = LinearGradient(
            padL, 0f, padL + fadeW, 0f, palette.background.toInt(), palette.background.withAlpha(0.0).toInt(), Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, padT, padL + fadeW, padT + chartH, fadePaint)

        // 6. Time axis.
        drawTimeAxis(canvas, w, padL, padR, padT + chartH, leftEdge, rightEdge, frameDt)

        // 7. Live dot with a pulse ring.
        val t = (nowMs % 1500.0) / 900.0
        if (t < 1) {
            val radius = dp(9f) + (t * dp(12f).toDouble()).toFloat()
            ringPaint.color = dotColor.withAlpha(dotColor.a * 0.35 * (1 - t)).toInt()
            canvas.drawCircle(endX, endY, radius, ringPaint)
        }
        canvas.drawCircle(endX, endY, dp(6.5f), dotOuter)
        dotInner.color = dotColor.toInt()
        canvas.drawCircle(endX, endY, dp(3.5f), dotInner)

        // 8. Endpoint value badge (momentum-tinted).
        badgePaint.color = when (trend) {
            Trend.UP -> palette.dotUp; Trend.DOWN -> palette.dotDown; else -> palette.badgeBg
        }.toInt()
        val label = fmt(displayValue)
        val tw = badgeText.measureText(label)
        val bx = padL + chartW + dp(10f); val bh = dp(22f); val bw = tw + dp(18f); val br = bh / 2
        canvas.drawRoundRect(bx, endY - bh / 2, bx + bw, endY + bh / 2, br, br, badgePaint)
        canvas.drawText(label, bx + dp(9f), endY + dp(4.5f), badgeText)
    }

    private fun fmt(v: Double): String = String.format("%.2f", v)

    // ── Time axis (ported from Swift LivelineView+Draw.drawTimeAxis) ────────────
    private class TimeLabel(var alpha: Double, var text: String)
    private val timeAlphas = HashMap<Long, TimeLabel>()
    private val timePatterns = HashMap<String, SimpleDateFormat>()

    private fun timeFmt(template: String) = timePatterns.getOrPut(template) {
        SimpleDateFormat(DateFormat.getBestDateTimePattern(Locale.getDefault(), template), Locale.getDefault())
    }

    private fun axisTimeLabel(t: Double, interval: Double): String {
        val template = when {
            interval >= 31_536_000 -> "yyyy"
            interval >= 2_592_000 -> "MMMyyyy"
            interval >= 86_400 -> "dMMM"
            interval >= 60 -> "jmm"
            else -> "jmmss"
        }
        return timeFmt(template).format(Date((t * 1000).toLong()))
    }

    private fun drawTimeAxis(
        canvas: Canvas, w: Float, padL: Float, padR: Float, lineY: Float,
        leftEdge: Double, rightEdge: Double, dt: Double,
    ) {
        val chartLeft = padL; val chartRight = w - padR; val chartW = chartRight - chartLeft
        val tickLen = dp(5f); val fadeZone = dp(50f)
        fun toX(t: Double) = chartLeft + ((t - leftEdge) / (rightEdge - leftEdge)).toFloat() * chartW
        fun edgeAlpha(x: Float): Double {
            val fromEdge = kotlin.math.min(x - chartLeft, chartRight - x)
            return when { fromEdge >= fadeZone -> 1.0; fromEdge <= 0f -> 0.0; else -> (fromEdge / fadeZone).toDouble() }
        }

        val targetPxPerSec = chartW / windowSeconds
        var interval = Intervals.niceTimeInterval(windowSeconds)
        while (interval * targetPxPerSec < 60 && interval < windowSeconds) interval *= 2

        val firstTime = ceil((leftEdge - interval) / interval) * interval
        val targetKeys = HashSet<Long>()
        var t = firstTime
        while (t <= rightEdge + interval && targetKeys.size < 30) { targetKeys.add(Math.round(t * 100)); t += interval }

        for (key in targetKeys) {
            val text = axisTimeLabel(key / 100.0, interval)
            val existing = timeAlphas[key]
            if (existing == null) timeAlphas[key] = TimeLabel(0.0, text) else existing.text = text
        }
        val remove = ArrayList<Long>()
        for ((key, label) in timeAlphas) {
            val x = toX(key / 100.0)
            val target = if (targetKeys.contains(key)) edgeAlpha(x) else 0.0
            var next = Clock.lerp(label.alpha, target, 0.08, dt)
            if (abs(next - target) < 0.02) next = target
            if (next < 0.01 && target == 0.0) remove.add(key) else label.alpha = next
        }
        for (k in remove) timeAlphas.remove(k)

        axisPaint.alpha = (palette.gridLine.a * 255).toInt()
        canvas.drawLine(chartLeft, lineY, chartRight, lineY, axisPaint)

        class L(val x: Float, val alpha: Double, val text: String, val wpx: Float)
        val list = ArrayList<L>()
        for ((key, label) in timeAlphas) {
            if (label.alpha < 0.02) continue
            val x = toX(key / 100.0)
            if (x < chartLeft - dp(20f) || x > chartRight) continue
            list.add(L(x, label.alpha, label.text, timeLabelPaint.measureText(label.text)))
        }
        list.sortBy { it.x }
        val drawn = ArrayList<L>()
        for (label in list) {
            val prev = drawn.lastOrNull()
            if (prev != null && label.x - label.wpx / 2 < prev.x + prev.wpx / 2 + dp(8f)) {
                if (label.alpha > prev.alpha) drawn[drawn.size - 1] = label
                continue
            }
            drawn.add(label)
        }
        val baseAxisA = palette.gridLine.a; val baseLabelA = palette.timeLabel.a
        for (label in drawn) {
            axisPaint.alpha = (baseAxisA * label.alpha * 255).toInt().coerceIn(0, 255)
            canvas.drawLine(label.x, lineY, label.x, lineY + tickLen, axisPaint)
            timeLabelPaint.alpha = (baseLabelA * label.alpha * 255).toInt().coerceIn(0, 255)
            canvas.drawText(label.text, label.x, lineY + tickLen + dp(12f), timeLabelPaint)
        }
    }
}

/** Straight-alpha [Rgba] → Android ARGB int. */
private fun Rgba.toInt(): Int = Color.argb(
    (a * 255).toInt().coerceIn(0, 255),
    (r * 255).toInt().coerceIn(0, 255),
    (g * 255).toInt().coerceIn(0, 255),
    (b * 255).toInt().coerceIn(0, 255),
)

/** Android ARGB int → straight-alpha [Rgba]. */
private fun Int.toRgba(): Rgba = Rgba(
    Color.red(this) / 255.0, Color.green(this) / 255.0, Color.blue(this) / 255.0, Color.alpha(this) / 255.0,
)
