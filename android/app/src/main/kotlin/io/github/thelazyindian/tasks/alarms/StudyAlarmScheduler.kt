package io.github.thelazyindian.tasks.alarms

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.util.Calendar

object StudyAlarmScheduler {
    private const val STORE = "nyro_user_alarms"
    fun preferences(context: Context) = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
    fun canSchedule(context: Context): Boolean {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return android.os.Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()
    }
    private fun pending(context: Context, id: Int): PendingIntent = PendingIntent.getBroadcast(
        context, id, Intent(context, StudyAlarmReceiver::class.java).setAction("NYRO_ALARM_FIRE").putExtra("id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    @Synchronized fun schedule(context: Context, value: JSONObject) {
        check(canSchedule(context)) { "Enable precise timing in Android settings before saving an alarm." }
        val id = value.getInt("id")
        val at = value.getLong("at")
        val calendar = Calendar.getInstance().apply { timeInMillis = at }
        if (!value.has("hour")) {
            value.put("hour", calendar.get(Calendar.HOUR_OF_DAY))
            value.put("minute", calendar.get(Calendar.MINUTE))
            value.put("weekday", calendar.get(Calendar.DAY_OF_WEEK))
        }
        preferences(context).edit().putString(id.toString(), value.toString()).commit()
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
        val show = PendingIntent.getActivity(context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        manager.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), pending(context, id))
    }
    @Synchronized fun cancelGroup(context: Context, group: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val prefs = preferences(context)
        prefs.all.forEach { (key, raw) ->
            try {
                val value = JSONObject(raw as String)
                if (value.getInt("group") == group) {
                    manager.cancel(pending(context, key.toInt()))
                    prefs.edit().remove(key).commit()
                }
            } catch (_: Exception) { }
        }
        if (StudyAlarmService.activeGroup == group) context.stopService(Intent(context, StudyAlarmService::class.java))
    }
    fun take(context: Context, id: Int): JSONObject? {
        val prefs = preferences(context)
        val value = prefs.getString(id.toString(), null)?.let { JSONObject(it) } ?: return null
        val interval = value.optInt("intervalDays", 0)
        if (interval > 0) {
            val next = JSONObject(value.toString())
            val calendar = Calendar.getInstance().apply { timeInMillis = value.getLong("at") }
            do { calendar.add(Calendar.DAY_OF_YEAR, interval) } while (calendar.timeInMillis <= System.currentTimeMillis())
            next.put("at", calendar.timeInMillis)
            try { schedule(context, next) } catch (_: SecurityException) { }
        } else prefs.edit().remove(id.toString()).commit()
        return value
    }
    fun restore(context: Context, clockChanged: Boolean = false) {
        if (!canSchedule(context)) return
        preferences(context).all.values.toList().forEach { raw ->
            try {
                val value = JSONObject(raw as String)
                if (value.optInt("intervalDays", 0) > 0 && (clockChanged || value.getLong("at") <= System.currentTimeMillis())) {
                    val calendar = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, value.getInt("hour")); set(Calendar.MINUTE, value.getInt("minute"))
                        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                    }
                    while (calendar.timeInMillis <= System.currentTimeMillis() ||
                        (value.optInt("intervalDays") == 7 && calendar.get(Calendar.DAY_OF_WEEK) != value.getInt("weekday"))) calendar.add(Calendar.DAY_OF_YEAR, 1)
                    value.put("at", calendar.timeInMillis)
                }
                if (value.getLong("at") > System.currentTimeMillis()) schedule(context, value)
                else preferences(context).edit().remove(value.getInt("id").toString()).commit()
            } catch (_: Exception) { }
        }
    }
}
