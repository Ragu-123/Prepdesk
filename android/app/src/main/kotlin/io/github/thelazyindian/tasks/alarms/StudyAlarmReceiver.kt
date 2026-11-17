package io.github.thelazyindian.tasks.alarms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class StudyAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        if (id < 0) return
        val value = StudyAlarmScheduler.take(context, id) ?: return
        ContextCompat.startForegroundService(context, Intent(context, StudyAlarmService::class.java)
            .setAction(StudyAlarmService.RING).putExtra("alarm", value.toString()))
    }
}

class StudyAlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        StudyAlarmScheduler.restore(context, intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED)
    }
}
