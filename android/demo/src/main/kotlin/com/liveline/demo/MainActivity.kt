package com.liveline.demo

import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.liveline.LivelineView
import com.liveline.core.LivelinePoint
import kotlin.random.Random

/** A native Android demo of the ported liveline engine + renderer. */
class MainActivity : AppCompatActivity() {
    private val chart by lazy { LivelineView(this) }
    private val handler = Handler(Looper.getMainLooper())
    private var value = 100.0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP
            setBackgroundColor(Color.parseColor("#0a0a0a"))
            setPadding(dp(20), dp(48), dp(20), dp(20))
        }
        root.addView(
            TextView(this).apply {
                text = "Liveline · Android"
                setTextColor(Color.WHITE); textSize = 26f; typeface = Typeface.DEFAULT_BOLD
            },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT),
        )
        root.addView(chart, LinearLayout.LayoutParams(MATCH_PARENT, dp(360)).apply { topMargin = dp(16) })
        root.addView(
            TextView(this).apply {
                text = "Shared android/liveline renderer — palette-driven, momentum badge, dashed baseline."
                setTextColor(Color.parseColor("#888888")); textSize = 13f
            },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(12) },
        )
        setContentView(root)

        // Backfill ~30s, then feed a calm mean-reverting walk every 100 ms.
        val now = System.currentTimeMillis() / 1000.0
        var v = 100.0
        val seed = (0 until 150).map { i ->
            v += (100 - v) * 0.02 + Random.nextDouble(-0.18, 0.18)
            LivelinePoint(now - 30 + i / 149.0 * 30, v)
        }
        value = v
        chart.setData(seed)
        startFeed()
    }

    private fun startFeed() {
        handler.post(object : Runnable {
            override fun run() {
                value += (100 - value) * 0.012 + Random.nextDouble(-0.06, 0.06)
                chart.push(LivelinePoint(System.currentTimeMillis() / 1000.0, value))
                handler.postDelayed(this, 100)
            }
        })
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacksAndMessages(null)
    }
}
