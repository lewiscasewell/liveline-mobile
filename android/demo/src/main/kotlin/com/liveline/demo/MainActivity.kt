package com.liveline.demo

import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/** A first native Android demo of the ported liveline engine. */
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#0a0a0a"))
            setPadding(dp(20), dp(48), dp(20), dp(20))
        }

        val title = TextView(this).apply {
            text = "Liveline · Android"
            setTextColor(Color.WHITE)
            textSize = 26f
            typeface = Typeface.DEFAULT_BOLD
        }
        root.addView(title, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        val chart = LivelineView(this)
        root.addView(
            chart,
            LinearLayout.LayoutParams(MATCH_PARENT, dp(360)).apply { topMargin = dp(16) },
        )

        val caption = TextView(this).apply {
            text = "Native Canvas render — the Kotlin engine (AutoRange → Domain → PathBuilder)."
            setTextColor(Color.parseColor("#888888"))
            textSize = 13f
        }
        root.addView(
            caption,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(12) },
        )

        root.gravity = Gravity.TOP
        setContentView(root)
    }
}
