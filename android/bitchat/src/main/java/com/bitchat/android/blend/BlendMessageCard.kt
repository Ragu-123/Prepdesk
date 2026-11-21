package com.bitchat.android.blend

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bitchat.android.model.BitchatMessage
import com.bitchat.android.services.AppStateStore

@Composable
internal fun BlendMessageCard(frame: BlendFrame, message: BitchatMessage, modifier: Modifier = Modifier) {
    val open = LocalBlendNavigation.current
    val controller = BlendController.get(LocalContext.current)
    val delivery by controller.delivery.collectAsStateWithLifecycle()
    val selectedPeer by AppStateStore.selectedPrivateChatPeer.collectAsStateWithLifecycle()
    val items = BlendProtocol.items(frame.data.optJSONArray("items"))
    OutlinedCard(
        onClick = { open(BlendOpen(peer = selectedPeer ?: message.senderPeerID, frame = frame)) },
        modifier = modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(frame.event.description, style = MaterialTheme.typography.titleSmall)
            if (frame.event == BlendEvent.CHECK_IN) Text(frame.data.optString("label").take(120))
            if (items.isNotEmpty()) Text("${items.size} study items · ${items.count { it.done }} done")
            delivery[message.id]?.let { Text(it, style = MaterialTheme.typography.labelSmall) }
            Text(if (frame.event == BlendEvent.SCHEDULE) "Open schedule" else "Open in Blend",
                style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
        }
    }
}
