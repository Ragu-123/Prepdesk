package com.bitchat.android.ui

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import com.bitchat.android.R

@Composable
internal fun BitChatNotificationActions(context: Context) {
    val systemNotifications = remember(context) { NotificationManagerCompat.from(context) }
    val chatNotifications = remember(context) {
        NotificationManager(context.applicationContext, systemNotifications)
    }
    Row(modifier = Modifier.padding(horizontal = 12.dp)) {
        TextButton(onClick = {
            if (chatNotifications.canPostPrivateAlerts()) {
                chatNotifications.postTestAlert()
            } else {
                context.startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                    putExtra(Settings.EXTRA_CHANNEL_ID, chatNotifications.privateAlertsChannel)
                })
            }
        }) {
            Text(stringResource(R.string.prepdesk_chat_test_action))
        }
        TextButton(onClick = {
            context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            })
        }) {
            Text(stringResource(R.string.prepdesk_chat_manage_alerts))
        }
    }
}
