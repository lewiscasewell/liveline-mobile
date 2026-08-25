package com.liveline.mobile

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
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
import com.liveline.core.PathBuilder
import com.liveline.core.Point
import com.liveline.core.Ticks
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.random.Random

/**
 * A first Android `Canvas` renderer for the ported liveline engine — line, area
 * fill, value grid, live dot and endpoint badge, driven by a `Choreographer`
 * frame loop and a synthetic random-walk feed. The maths (range, easing, spline)
 * all come from `com.liveline.core`; this class only maps to pixels and paints.
 */
class LivelineView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs), Choreographer.FrameCallback {

    private val windowSeconds = 30.0
    private val accent = Color.parseColor("#3b82f6")

    private val buffer = ArrayList<LivelinePoint>()
    private val domain = Domain()
    private var value = 100.0
    private var displayValue = 100.0
    private var gridInterval = 0.0

    private var lastFrameMs = 0.0
    private var lastFeedMs = 0.0
    private var lastCommitSec = 0.0
    private var frameDt = Clock.FRAME_MS

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(2f)
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = accent
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val fadePaint = Paint().apply { style = Paint.Style.FILL }
    private val backgroundColor = Color.parseColor("#0a0a0a")
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(1f)
        color = Color.argb(16, 255, 255, 255)
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(110, 255, 255, 255)
        textSize = dp(11f)
        typeface = Typeface.MONOSPACE
    }
    private val timeLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(110, 255, 255, 255)
        textSize = dp(11f)
        typeface = Typeface.MONOSPACE
        textAlign = Paint.Align.CENTER
    }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(1f)
        color = Color.argb(16, 255, 255, 255)
    }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = (accent and 0x00FFFFFF) or (0x40 shl 24)
    }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.WHITE
    }
    private val dotInner = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = accent
    }
    private val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = accent
    }
    private val badgeText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = dp(13f)
        typeface = Typeface.MONOSPACE
    }

    init {
        // Backfill ~30s so the chart opens populated.
        val now = System.currentTimeMillis() / 1000.0
        var v = 100.0
        val n = 150
        for (i in 0 until n) {
            v += (100 - v) * 0.02 + Random.nextDouble(-0.18, 0.18)
            buffer.add(LivelinePoint(now - windowSeconds + i / (n - 1.0) * windowSeconds, v))
        }
        value = v
        displayValue = v
    }

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
        // Frame delta from the display clock, so easing is frame-rate independent.
        frameDt = if (lastFrameMs == 0.0) Clock.FRAME_MS else (nowMs - lastFrameMs).coerceIn(1.0, 64.0)
        lastFrameMs = nowMs

        // Feed a new sample ~ every 100 ms (a calm mean-reverting walk).
        if (nowMs - lastFeedMs > 100) {
            lastFeedMs = nowMs
            value += (100 - value) * 0.012 + Random.nextDouble(-0.06, 0.06)
            val t = System.currentTimeMillis() / 1000.0
            val bucket = windowSeconds / 300.0
            if (buffer.isEmpty() || t - lastCommitSec >= bucket) {
                buffer.add(LivelinePoint(t, value))
                lastCommitSec = t
                if (buffer.size > 4096) buffer.removeAt(0)
            } else {
                buffer[buffer.size - 1] = LivelinePoint(t, value)
            }
        }
        invalidate()
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return

        val dt = frameDt

        val padL = dp(8f)
        val padR = dp(64f)
        val padT = dp(12f)
        val padB = dp(30f)
        val chartW = w - padL - padR
        val chartH = h - padT - padB

        val now = System.currentTimeMillis() / 1000.0
        val rightEdge = now + windowSeconds * 0.05
        val leftEdge = rightEdge - windowSeconds

        // Visible points (one before the left edge for a clean entry).
        var startIdx = 0
        for (i in buffer.indices) {
            if (buffer[i].time >= leftEdge) {
                startIdx = max(0, i - 1)
                break
            }
        }
        val visible = ArrayList<LivelinePoint>()
        for (i in startIdx until buffer.size) {
            if (buffer[i].time <= now) visible.add(buffer[i])
        }
        if (visible.size < 2) return

        // Ease the live value + range using the shared maths (adaptive speed:
        // slower for big jumps, faster for small ticks — matches iOS/web).
        val speed = Domain.adaptiveSpeed(value, displayValue, domain.minVal, domain.maxVal, 0.06)
        displayValue = Clock.lerp(displayValue, value, speed, dt)
        val values = visible.map { it.value }
        val target = AutoRange.compute(values, displayValue)
        domain.update(target, speed, dt, chartH.toDouble())

        val minV = domain.minVal
        val range = domain.valRange
        val maxV = domain.maxVal
        fun toX(t: Double) = padL + ((t - leftEdge) / (rightEdge - leftEdge)).toFloat() * chartW
        fun toY(v: Double) = padT + ((maxV - v) / range).toFloat() * chartH

        // Grid + right-edge value labels.
        val pxPerUnit = chartH / range
        gridInterval = Ticks.pickInterval(range, pxPerUnit.toDouble(), dp(36f).toDouble(), gridInterval)
        if (gridInterval > 0) {
            var g = kotlin.math.ceil(minV / gridInterval) * gridInterval
            while (g <= maxV) {
                val y = toY(g)
                canvas.drawLine(padL, y, padL + chartW, y, gridPaint)
                canvas.drawText(fmt(g), padL + chartW + dp(6f), y + dp(4f), labelPaint)
                g += gridInterval
            }
        }

        // Map the visible samples, then ride the head at the continuously-
        // advancing `now` and the eased value — so the line extends smoothly
        // every frame instead of stepping with the raw feed.
        val endX = toX(now)
        val endY = toY(displayValue)
        val pts = ArrayList<Point>(visible.size)
        for (p in visible) pts.add(Point(toX(p.time).toDouble(), toY(p.value).toDouble()))
        pts[pts.size - 1] = Point(endX.toDouble(), endY.toDouble())

        // Spline path via the shared Fritsch–Carlson builder.
        val path = Path()
        path.moveTo(pts[0].x.toFloat(), pts[0].y.toFloat())
        for (s in PathBuilder.monotoneSegments(pts)) {
            path.cubicTo(
                s.control1.x.toFloat(), s.control1.y.toFloat(),
                s.control2.x.toFloat(), s.control2.y.toFloat(),
                s.end.x.toFloat(), s.end.y.toFloat(),
            )
        }

        // Area fill.
        val fill = Path(path)
        fill.lineTo(pts.last().x.toFloat(), padT + chartH)
        fill.lineTo(pts.first().x.toFloat(), padT + chartH)
        fill.close()
        fillPaint.shader = LinearGradient(
            0f, padT, 0f, padT + chartH,
            (accent and 0x00FFFFFF) or (0x22 shl 24), Color.TRANSPARENT, Shader.TileMode.CLAMP,
        )
        canvas.drawPath(fill, fillPaint)
        canvas.drawPath(path, linePaint)

        // Left-edge fade: the line dissolves into the background as it scrolls
        // off the left, instead of clipping abruptly.
        val fadeW = dp(56f)
        fadePaint.shader = LinearGradient(
            padL, 0f, padL + fadeW, 0f,
            backgroundColor, (backgroundColor and 0x00FFFFFF), Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, padT, padL + fadeW, padT + chartH, fadePaint)

        // Bottom time axis (formatted, smoothly scrolling + fading ticks).
        drawTimeAxis(canvas, w, padL, padR, padT + chartH, leftEdge, rightEdge, dt)

        // Live dot with a soft ring.
        canvas.drawCircle(endX, endY, dp(9f), ringPaint)
        canvas.drawCircle(endX, endY, dp(6.5f), dotPaint)
        canvas.drawCircle(endX, endY, dp(3.5f), dotInner)

        // Endpoint value badge.
        val label = fmt(displayValue)
        val tw = badgeText.measureText(label)
        val bx = padL + chartW + dp(10f)
        val bh = dp(22f)
        val bw = tw + dp(18f)
        val br = bh / 2
        canvas.drawRoundRect(bx, endY - bh / 2, bx + bw, endY + bh / 2, br, br, badgePaint)
        canvas.drawText(label, bx + dp(9f), endY + dp(4.5f), badgeText)
    }

    private fun fmt(v: Double): String = String.format("%.2f", v)

    // ── Time axis (a 1-for-1 port of Swift LivelineView+Draw.drawTimeAxis) ──────

    private class TimeLabel(var alpha: Double, var text: String)

    /** Per-tick fade state, keyed by round(t * 100) — mirrors Swift `timeAlphas`.
     *  Long, not Int: a unix time × 100 overflows a 32-bit Int. */
    private val timeAlphas = HashMap<Long, TimeLabel>()
    private val timePatterns = HashMap<String, SimpleDateFormat>()

    private fun timeFmt(template: String): SimpleDateFormat = timePatterns.getOrPut(template) {
        val pattern = DateFormat.getBestDateTimePattern(Locale.getDefault(), template)
        SimpleDateFormat(pattern, Locale.getDefault())
    }

    /** Axis label for a tick at time [t] (seconds), format chosen from [interval]. */
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
        canvas: Canvas,
        w: Float,
        padL: Float,
        padR: Float,
        lineY: Float,
        leftEdge: Double,
        rightEdge: Double,
        dt: Double,
    ) {
        val chartLeft = padL
        val chartRight = w - padR
        val chartW = chartRight - chartLeft
        val tickLen = dp(5f)
        val fadeZone = dp(50f)

        fun toX(t: Double) = chartLeft + ((t - leftEdge) / (rightEdge - leftEdge)).toFloat() * chartW
        fun edgeAlpha(x: Float): Double {
            val fromEdge = kotlin.math.min(x - chartLeft, chartRight - x)
            return when {
                fromEdge >= fadeZone -> 1.0
                fromEdge <= 0f -> 0.0
                else -> (fromEdge / fadeZone).toDouble()
            }
        }

        val targetPxPerSec = chartW / windowSeconds
        var interval = Intervals.niceTimeInterval(windowSeconds)
        while (interval * targetPxPerSec < 60 && interval < windowSeconds) interval *= 2

        val firstTime = ceil((leftEdge - interval) / interval) * interval
        val targetKeys = HashSet<Long>()
        var t = firstTime
        while (t <= rightEdge + interval && targetKeys.size < 30) {
            targetKeys.add(Math.round(t * 100))
            t += interval
        }

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

        // Bottom axis line.
        axisPaint.alpha = 16
        canvas.drawLine(chartLeft, lineY, chartRight, lineY, axisPaint)

        // Collect + resolve overlaps (keep the brighter of two clashing labels).
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
            val left = label.x - label.wpx / 2
            val prev = drawn.lastOrNull()
            if (prev != null && left < prev.x + prev.wpx / 2 + dp(8f)) {
                if (label.alpha > prev.alpha) drawn[drawn.size - 1] = label
                continue
            }
            drawn.add(label)
        }

        for (label in drawn) {
            val a = label.alpha
            axisPaint.alpha = (16 * a).toInt().coerceIn(0, 255)
            canvas.drawLine(label.x, lineY, label.x, lineY + tickLen, axisPaint)
            timeLabelPaint.alpha = (110 * a).toInt().coerceIn(0, 255)
            canvas.drawText(label.text, label.x, lineY + tickLen + dp(12f), timeLabelPaint)
        }
    }
}
