package com.bitchat.android.blend

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.outlined.JoinInner
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.bitchat.android.R
import com.bitchat.android.services.ContactDirectory

@Composable
internal fun BlendIcon(modifier: Modifier = Modifier) {
    Icon(Icons.Outlined.JoinInner, contentDescription = null,
        modifier = modifier, tint = MaterialTheme.colorScheme.primary)
}

@Composable
internal fun BlendNetworkEntry() {
    val open = LocalBlendNavigation.current
    val controller = BlendController.get(LocalContext.current)
    val sessions by controller.sessions.collectAsStateWithLifecycle()
    val visible = sessions.filter { !it.stopped }.asReversed()
    Text(stringResource(R.string.prepdesk_blend),
        modifier = Modifier.padding(start = 16.dp, top = 24.dp, bottom = 4.dp),
        style = MaterialTheme.typography.titleMedium)
    if (visible.isEmpty()) {
        Text(stringResource(R.string.prepdesk_blend_empty),
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    visible.forEach { session ->
    val name = ContactDirectory.resolve(session.peer).displayName ?: stringResource(R.string.prepdesk_blend_contact)
    ListItem(
        modifier = Modifier.fillMaxWidth().clickable {
            open(BlendOpen(peer = session.peer, sessionId = session.id))
        },
        headlineContent = { Text(name) },
        supportingContent = {
            Text(when {
                !session.active && !session.owner -> "Invitation to review"
                !session.active -> "Invitation sent"
                session.role == BlendRole.SPECTATOR -> "Watching"
                else -> session.mode.label
            })
        },
        leadingContent = { BlendIcon() },
        trailingContent = { Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null) }
    )
    }
}
