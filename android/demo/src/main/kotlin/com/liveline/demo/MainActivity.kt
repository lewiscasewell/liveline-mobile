package com.liveline.demo

import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import com.liveline.LivelineView
import com.liveline.WindowBarView
import com.liveline.core.BadgeVariant
import com.liveline.core.LivelineCandle
import com.liveline.core.LivelineMode
import com.liveline.core.LivelinePoint
import com.liveline.core.LivelineTheme
import com.liveline.core.Momentum
import com.liveline.core.OrderbookData
import com.liveline.core.OrderbookLevel
import com.liveline.core.ReferenceLine
import kotlin.random.Random

/** A native Android showcase mirroring the iOS ContentView demo menu. */
class MainActivity : AppCompatActivity() {

    private enum class Kind { WALK, SPIKES, SLOW, STALE, LOADING, PAUSED, CANDLE, ORDERBOOK }

    private class Demo(
        val name: String,
        val subtitle: String,
        val center: Double = 100.0,
        val vol: Double = 0.9,
        val intervalMs: Long = 100,
        val kind: Kind = Kind.WALK,
        val window: Double = 30.0,
        val windowBar: List<WindowBarView.Window>? = null,
        val configure: (LivelineView) -> Unit = {},
    )

    private val demos = listOf(
        Demo("Basic", "A live value; accent badge.") { it.momentum = Momentum.OFF },
        Demo("Momentum", "Chevrons + green/red badge.", vol = 1.3) { it.momentum = Momentum.AUTO },
        Demo("Value overlay", "showValue, tinted by momentum.", center = 9800.0, vol = 24.0) {
            it.showValue = true; it.valueMomentumColor = true; it.valuePrefix = "$"
        },
        Demo("Reference line", "A marker kept in view.", center = 67_500.0, vol = 240.0) {
            it.accent = Color.parseColor("#8b5cf6"); it.valuePrefix = "$"; it.valueDecimals = 0
            it.referenceLine = ReferenceLine(67_500.0, "Above \$67,500")
        },
        Demo("Heart rate", "Exaggerated Y, bpm.", center = 62.0, vol = 0.4) {
            it.accent = Color.parseColor("#e5493d"); it.exaggerate = true; it.valueSuffix = " bpm"; it.valueDecimals = 0
        },
        Demo("CPU usage", "Low baseline + spikes.", center = 14.0, kind = Kind.SPIKES) {
            it.accent = Color.parseColor("#4aad66"); it.valueSuffix = "%"; it.valueDecimals = 0
        },
        Demo("Slow ticker", "One update / 4s.", intervalMs = 4000, kind = Kind.SLOW, window = 60.0) {
            it.accent = Color.parseColor("#8b5cf6")
        },
        Demo(
            "Time windows", "Tap a chip to zoom the interval.", vol = 1.2, window = 60.0,
            windowBar = listOf(WindowBarView.Window("30s", 30.0), WindowBarView.Window("1m", 60.0), WindowBarView.Window("5m", 300.0)),
        ) { it.accent = Color.parseColor("#f0a020") },
        Demo("Candlestick", "OHLC candles + a live candle.", intervalMs = 60, kind = Kind.CANDLE, window = 54.0) {
            it.mode = LivelineMode.CANDLE; it.valueDecimals = 1
        },
        Demo("Orderbook", "Bid/ask sizes stream up behind the line.", center = 62.0, vol = 0.8, kind = Kind.ORDERBOOK, window = 45.0) {
            it.valueSuffix = "¢"; it.valueDecimals = 0
        },
        Demo("Degen", "Shake + sparks on strong up-moves.", center = 420.0, vol = 6.0) {
            it.momentum = Momentum.AUTO; it.degen = true; it.badgeVariant = BadgeVariant.ACCENT
            it.accent = Color.parseColor("#f0731a"); it.valueDecimals = 1
        },
        Demo("Loading", "Breathing, then data.", kind = Kind.LOADING) {},
        Demo("Paused", "Freezes, then catches up.", center = 160.0, vol = 1.0, kind = Kind.PAUSED) {
            it.accent = Color.parseColor("#4aad66")
        },
        Demo("Stale feed", "Feed stops after 6s.", kind = Kind.STALE) {},
    )

    private lateinit var chart: LivelineView
    private lateinit var subtitle: TextView
    private lateinit var root: LinearLayout
    private lateinit var windowBar: WindowBarView
    private val handler = Handler(Looper.getMainLooper())
    private var dark = true
    private var v = 100.0
    private var spike = 0.0
    private var ticks = 0
    private var elapsedMs = 0L
    private val candleWidth = 3.0
    private var candlePrice = 150.0
    private val candleList = ArrayList<LivelineCandle>()
    private var liveC = LivelineCandle(0.0, 150.0, 150.0, 150.0, 150.0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        fun dp(x: Int) = (x * resources.displayMetrics.density).toInt()

        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.TOP
            setPadding(dp(20), dp(44), dp(20), dp(20))
        }
        root.addView(TextView(this).apply { text = "Liveline · Android"; textSize = 24f; typeface = Typeface.DEFAULT_BOLD },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        val controls = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        val themeBtn = Button(this).apply { text = "Dark"; setOnClickListener { dark = !dark; text = if (dark) "Dark" else "Light"; applyTheme() } }
        val spinner = Spinner(this)
        spinner.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, demos.map { it.name })
        spinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(p: AdapterView<*>?, view: View?, pos: Int, id: Long) = selectDemo(pos)
            override fun onNothingSelected(p: AdapterView<*>?) {}
        }
        controls.addView(themeBtn, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { rightMargin = dp(12) })
        controls.addView(spinner, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        root.addView(controls, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(12) })

        chart = LivelineView(this)
        root.addView(chart, LinearLayout.LayoutParams(MATCH_PARENT, dp(320)).apply { topMargin = dp(16) })
        windowBar = WindowBarView(this).apply { visibility = View.GONE; onSelect = { chart.windowSeconds = it } }
        root.addView(windowBar, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { topMargin = dp(12); gravity = Gravity.CENTER_HORIZONTAL })
        subtitle = TextView(this).apply { textSize = 13f }
        root.addView(subtitle, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(12) })

        setContentView(root)
        applyTheme()
        selectDemo(0)
    }

    private fun applyTheme() {
        root.setBackgroundColor(if (dark) Color.parseColor("#0a0a0a") else Color.WHITE)
        val fg = if (dark) Color.WHITE else Color.parseColor("#111111")
        (root.getChildAt(0) as TextView).setTextColor(fg)
        subtitle.setTextColor(if (dark) Color.parseColor("#888888") else Color.parseColor("#666666"))
        chart.theme = if (dark) LivelineTheme.DARK else LivelineTheme.LIGHT
        windowBar.isDark = dark
    }

    private fun selectDemo(index: Int) {
        val demo = demos[index]
        handler.removeCallbacksAndMessages(null)
        subtitle.text = demo.subtitle

        // Reset config to defaults, then apply the demo's.
        chart.apply {
            momentum = Momentum.AUTO; badgeVariant = BadgeVariant.DEFAULT
            showValue = false; valueMomentumColor = false; exaggerate = false
            loading = false; paused = false; referenceLine = null; degen = false
            valuePrefix = ""; valueSuffix = ""; valueDecimals = 2
            accent = Color.parseColor("#3b82f6"); windowSeconds = demo.window
            mode = LivelineMode.LINE; setCandles(emptyList(), null, 1.0); orderbook = null
        }
        demo.configure(chart)

        // Interval bar (only for the Time windows demo).
        if (demo.windowBar != null) {
            windowBar.visibility = View.VISIBLE
            windowBar.isDark = dark
            windowBar.setWindows(demo.windowBar, demo.window)
        } else windowBar.visibility = View.GONE

        if (demo.kind == Kind.CANDLE) { seedCandles(); startFeed(demo); return }

        // Seed a backfill.
        val now = System.currentTimeMillis() / 1000.0
        v = demo.center; spike = 0.0; ticks = 0; elapsedMs = 0
        val n = 150; val span = demo.window
        val seed = (0 until n).map { i ->
            v += (demo.center - v) * 0.02 + Random.nextDouble(-demo.vol * 0.3, demo.vol * 0.3)
            LivelinePoint(now - span + i / (n - 1.0) * span, v)
        }
        v = demo.center
        chart.setData(seed)
        if (demo.kind == Kind.LOADING) chart.loading = true
        startFeed(demo)
    }

    private fun seedCandles() {
        candleList.clear(); elapsedMs = 0
        val nowSec = System.currentTimeMillis() / 1000.0
        val liveBucket = floor(nowSec / candleWidth) * candleWidth
        var p = 150.0
        for (i in 0 until 18) {
            val open = p; var hi = open; var lo = open
            repeat(10) { p += Random.nextDouble(-1.8, 1.8); hi = max(hi, p); lo = min(lo, p) }
            candleList.add(LivelineCandle(liveBucket - candleWidth * (18 - i), open, hi, lo, p))
        }
        candlePrice = p
        liveC = LivelineCandle(liveBucket, p, p, p, p)
        chart.setCandles(ArrayList(candleList), liveC, candleWidth)
    }

    private fun startFeed(demo: Demo) {
        handler.post(object : Runnable {
            override fun run() {
                elapsedMs += demo.intervalMs
                when (demo.kind) {
                    Kind.SPIKES -> {
                        v += (demo.center - v) * 0.05 + Random.nextDouble(-2.0, 2.0)
                        if (Random.nextDouble() > 0.97) spike = Random.nextDouble(40.0, 75.0)
                        spike *= 0.82
                        chart.push(LivelinePoint(System.currentTimeMillis() / 1000.0, (v + spike).coerceIn(2.0, 100.0)))
                    }
                    Kind.SLOW -> { v += Random.nextDouble(-5.0, 5.0); chart.push(LivelinePoint(System.currentTimeMillis() / 1000.0, v)) }
                    Kind.STALE -> if (elapsedMs <= 6000) { v += (demo.center - v) * 0.01 + Random.nextDouble(-demo.vol, demo.vol); chart.push(LivelinePoint(System.currentTimeMillis() / 1000.0, v)) }
                    Kind.LOADING -> { if (elapsedMs >= 3000) chart.loading = false; v += (demo.center - v) * 0.01 + Random.nextDouble(-demo.vol, demo.vol); chart.push(LivelinePoint(System.currentTimeMillis() / 1000.0, v)) }
                    Kind.PAUSED -> { chart.paused = (elapsedMs / 4000) % 2 == 1L; v += (demo.center - v) * 0.01 + Random.nextDouble(-demo.vol, demo.vol); chart.push(LivelinePoint(System.currentTimeMillis() / 1000.0, v)) }
                    Kind.WALK -> { v += (demo.center - v) * 0.012 + Random.nextDouble(-demo.vol * 0.35, demo.vol * 0.35); chart.push(LivelinePoint(System.currentTimeMillis() / 1000.0, v)) }
                    Kind.ORDERBOOK -> {
                        v += (demo.center - v) * 0.008 + Random.nextDouble(-0.8, 0.8)
                        chart.push(LivelinePoint(System.currentTimeMillis() / 1000.0, v))
                        val bids = ArrayList<OrderbookLevel>(); val asks = ArrayList<OrderbookLevel>()
                        for (i in 0 until 6) {
                            val dPr = i * 0.12 + 0.08
                            val bidSize = if (Random.nextDouble() > 0.9) Random.nextDouble(80.0, 260.0) else Random.nextDouble(4.0, 70.0)
                            val askSize = if (Random.nextDouble() > 0.9) Random.nextDouble(80.0, 260.0) else Random.nextDouble(4.0, 70.0)
                            bids.add(OrderbookLevel(v - dPr, bidSize)); asks.add(OrderbookLevel(v + dPr, askSize))
                        }
                        chart.orderbook = OrderbookData(bids, asks)
                    }
                    Kind.CANDLE -> {
                        candlePrice += Random.nextDouble(-1.8, 1.8)
                        val bucket = floor(System.currentTimeMillis() / 1000.0 / candleWidth) * candleWidth
                        if (bucket != liveC.time) {
                            candleList.add(liveC); if (candleList.size > 40) candleList.removeAt(0)
                            liveC = LivelineCandle(bucket, candlePrice, candlePrice, candlePrice, candlePrice)
                        } else liveC = LivelineCandle(liveC.time, liveC.open, max(liveC.high, candlePrice), min(liveC.low, candlePrice), candlePrice)
                        chart.setCandles(ArrayList(candleList), liveC, candleWidth)
                    }
                }
                handler.postDelayed(this, demo.intervalMs)
            }
        })
    }

    override fun onDestroy() { super.onDestroy(); handler.removeCallbacksAndMessages(null) }
}
