package io.github.thelazyindian.tasks.alarms

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.text.DateFormat
import java.util.Date

class StudyAlarmActivity : Activity() {
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private var currentId = -1
    private val checkRinging = object : Runnable {
        override fun run() {
            if (StudyAlarmService.activeId != currentId) finish()
            else handler.postDelayed(this, 1000)
        }
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); super.onDestroy() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else @Suppress("DEPRECATION") window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        render()
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); render() }
    private fun render() {
        val raw = intent.getStringExtra("alarm") ?: run { finish(); return }
        val alarm = try { JSONObject(raw) } catch (_: Exception) { finish(); return }
        currentId = alarm.getInt("id")
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed(checkRinging, 1000)
        val appearance = getSharedPreferences("nyro_appearance", MODE_PRIVATE)
        val accent = if (appearance.getBoolean("adaptive", true))
            appearance.getInt("accent", 0xFF315DA8.toInt()) else 0xFF315DA8.toInt()
        val container = androidx.core.graphics.ColorUtils.blendARGB(Color.WHITE, accent, 0.15f)
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            setPadding(dp(28), dp(48), dp(28), dp(40)); setBackgroundColor(Color.rgb(247, 248, 252))
        }
        val typeface = try { Typeface.createFromAsset(assets, "flutter_assets/assets/google_fonts/NotoSans-Regular.ttf") } catch (_: Exception) { Typeface.DEFAULT }
        fun label(value: String, size: Float, bold: Boolean = false) = TextView(this).apply {
            text = value; textSize = size; gravity = Gravity.CENTER; setTextColor(Color.rgb(32, 38, 48))
            setTypeface(typeface, if (bold) Typeface.BOLD else Typeface.NORMAL)
            setPadding(0, dp(12), 0, dp(12))
        }
        val symbol = android.widget.ImageView(this).apply {
            setImageResource(io.github.thelazyindian.tasks.R.drawable.ic_nyro_notification)
            imageTintList = android.content.res.ColorStateList.valueOf(accent)
            contentDescription = null
        }
        layout.addView(symbol, LinearLayout.LayoutParams(dp(48), dp(48)))
        layout.addView(label("Study alarm", 16f))
        layout.addView(label(DateFormat.getTimeInstance(DateFormat.SHORT).format(Date()), 58f))
        layout.addView(label(alarm.optString("title", "Study reminder"), 26f, true))
        layout.addView(label(getString(io.github.thelazyindian.tasks.R.string.app_name), 14f))
        fun button(title: String, action: String, minutes: Int = 0) {
            val control = Button(this).apply {
                text = title; isAllCaps = false; textSize = 16f; minimumHeight = dp(56)
                setTextColor(if (action == StudyAlarmService.DISMISS) Color.WHITE else accent)
                background = GradientDrawable().apply { cornerRadius = dp(28).toFloat(); setColor(if (action == StudyAlarmService.DISMISS) accent else container) }
                setOnClickListener {
                    startService(Intent(this@StudyAlarmActivity, StudyAlarmService::class.java)
                        .setAction(action).putExtra("alarm", raw).putExtra("minutes", minutes))
                    finish()
                }
            }
            layout.addView(control, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(56)).apply { topMargin = dp(16) })
        }
        button("Snooze 5 minutes", StudyAlarmService.SNOOZE, 5)
        button("Snooze 10 minutes", StudyAlarmService.SNOOZE, 10)
        button("Dismiss alarm", StudyAlarmService.DISMISS)
        setContentView(ScrollView(this).apply { isFillViewport = true; addView(layout) })
    }
    @Deprecated("Use the visible snooze or dismiss controls")
    override fun onBackPressed() { }
}
