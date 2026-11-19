package com.bitchat.android.integration

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.bitchat.android.R

internal val Context.prepdeskAppearanceUri: Uri
    get() = Uri.parse("content://$packageName.appearance")

internal fun prepdeskChatNotification(context: Context, channel: String): NotificationCompat.Builder {
    val accent = runCatching {
        context.contentResolver.call(context.prepdeskAppearanceUri, "notificationStyle", null, null)
            ?.getInt("accent")
    }.getOrNull() ?: 0xFF315DA8.toInt()
    return NotificationCompat.Builder(context, channel)
        .setSmallIcon(R.drawable.ic_nyro_notification)
        .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.drawable.nyro_notification_logo))
        .setColor(accent)
        .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
}
