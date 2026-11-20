package com.bitchat.android.integration

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.graphics.Color
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.graphics.ColorUtils
import com.bitchat.android.R

internal val Context.prepdeskAppearanceUri: Uri
    get() = Uri.parse("content://$packageName.appearance")

internal fun chatAccent(context: Context): Int = runCatching {
        context.contentResolver.call(context.prepdeskAppearanceUri, "notificationStyle", null, null)
            ?.getInt("accent")
}.getOrNull() ?: 0xFF315DA8.toInt()

internal fun prepdeskChatNotification(context: Context, channel: String): NotificationCompat.Builder =
    NotificationCompat.Builder(context, channel)
        .setSmallIcon(R.drawable.ic_nyro_notification)
        .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.drawable.nyro_notification_logo))
        .setColor(chatAccent(context))
        .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)

internal fun NotificationCompat.Builder.withPrepdeskChatBanner(
    context: Context, title: CharSequence, body: CharSequence
): NotificationCompat.Builder {
    val accent = chatAccent(context)
    val text = if (ColorUtils.calculateContrast(Color.WHITE, accent) >= 4.5) Color.WHITE else Color.BLACK
    val banner = RemoteViews(context.packageName, R.layout.prepdesk_chat_heads_up).apply {
        setInt(R.id.chat_banner, "setBackgroundColor", accent)
        setTextViewText(R.id.chat_banner_title, title)
        setTextViewText(R.id.chat_banner_body, body)
        setTextColor(R.id.chat_banner_title, text)
        setTextColor(R.id.chat_banner_body, text)
    }
    return setCustomHeadsUpContentView(banner)
}
