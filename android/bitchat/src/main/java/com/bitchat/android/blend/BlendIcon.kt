package com.bitchat.android.blend

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.JoinInner
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

@Composable
internal fun BlendIcon(modifier: Modifier = Modifier) {
    Icon(
        Icons.Outlined.JoinInner,
        contentDescription = null,
        modifier = modifier,
        tint = MaterialTheme.colorScheme.primary
    )
}
