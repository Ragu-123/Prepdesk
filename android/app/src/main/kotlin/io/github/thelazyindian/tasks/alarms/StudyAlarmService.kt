package io.github.thelazyindian.tasks.alarms

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import io.github.thelazyindian.tasks.MainActivity
import io.github.thelazyindian.tasks.R
import org.json.JSONObject

class StudyAlarmService : Service() {
    companion object {
        const val RING = "NYRO_RING"
        const val DISMISS = "NYRO_DISMISS"
        const val SNOOZE = "NYRO_SNOOZE"
        const val CHANNEL = "nyro_clock_alarms_v1"
        @Volatile var activeGroup: Int? = null
        @Volatile var activeId: Int? = null
    }
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var vibrator: Vibrator? = null
    private fun command(value: JSONObject, action: String, minutes: Int = 0): PendingIntent {
        val intent = Intent(this, StudyAlarmService::class.java).setAction(action)
            .setData(android.net.Uri.parse("nyro-alarm://" + value.getInt("id") + "/" + action + "/" + minutes))
            .putExtra("alarm", value.toString()).putExtra("minutes", minutes)
        return PendingIntent.getService(this, value.getInt("id") + minutes, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val value = try { JSONObject(intent?.getStringExtra("alarm") ?: return START_NOT_STICKY) } catch (_: Exception) { return START_NOT_STICKY }
        if (intent?.action == DISMISS || intent?.action == SNOOZE) {
            if (intent.action == SNOOZE) {
                val snooze = JSONObject(value.toString())
                var id: Int
                do { id = 0x50000000 or kotlin.random.Random.nextInt(0x0fffffff) }
                while (StudyAlarmScheduler.preferences(this).contains(id.toString()))
                snooze.put("id", id).put("intervalDays", 0)
                    .put("at", System.currentTimeMillis() + intent.getIntExtra("minutes", 5) * 60000L)
                StudyAlarmScheduler.schedule(this, snooze)
            }
            if (activeId == null || activeId == value.getInt("id")) stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Ringing alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "User-scheduled alarms with looping alarm audio"
                setSound(null, null); enableVibration(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            })
        }
        if (activeId != null) {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        releaseAudio()
        activeGroup = value.getInt("group"); activeId = value.getInt("id")
        val screen = Intent(this, StudyAlarmActivity::class.java)
            .putExtra("alarm", value.toString()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val fullScreen = PendingIntent.getActivity(this, value.getInt("id"), screen,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val title = android.text.SpannableString(value.optString("title", "Study alarm")).apply {
            setSpan(android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, length, 0)
        }
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_alarm_notification).setContentTitle(title)
            .setStyle(NotificationCompat.BigTextStyle().setBigContentTitle(title)
                .bigText(value.optString("body").takeIf { it.isNotBlank() && it != title.toString() } ?: "Your study alarm is ringing. Snooze or dismiss when ready."))
            .setSubText("Study alarm").setWhen(value.optLong("at", System.currentTimeMillis())).setShowWhen(true)
            .setContentText("Alarm ringing. Snooze or dismiss.")
            .setPriority(NotificationCompat.PRIORITY_MAX).setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).setOngoing(true).setAutoCancel(false)
            .setContentIntent(fullScreen).setFullScreenIntent(fullScreen, true)
            .addAction(0, "Snooze 5m", command(value, SNOOZE, 5))
            .addAction(0, "Snooze 10m", command(value, SNOOZE, 10))
            .addAction(0, "Dismiss", command(value, DISMISS)).build()
        startForeground(value.getInt("id"), notification)
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "NYRO:StudyAlarm").apply { acquire(125000L) }
        val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                setDataSource(this@StudyAlarmService, alarmSound); isLooping = true
                prepare(); start()
            }
        } catch (_: Exception) { player?.release(); player = null }
        @Suppress("DEPRECATION")
        vibrator = (getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)
        val pattern = longArrayOf(0, 600, 500)
        if (Build.VERSION.SDK_INT >= 26) vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        else @Suppress("DEPRECATION") vibrator?.vibrate(pattern, 0)
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({ stopSelf() }, 120000L)
        if (MainActivity.isVisible) startActivity(screen)
        return START_NOT_STICKY
    }
    private fun releaseAudio() {
        try { player?.stop() } catch (_: Exception) { }
        player?.release(); player = null
        vibrator?.cancel()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null); releaseAudio()
        activeGroup = null; activeId = null
        @Suppress("DEPRECATION")
        stopForeground(true)
        super.onDestroy()
    }
}
