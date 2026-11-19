package com.bitchat.android.integration

import android.content.Intent
import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class PrepdeskAppearance(
    val primary: Color,
    val primaryContainer: Color,
    val onPrimaryContainer: Color,
    val background: Color,
    val surface: Color,
    val onSurface: Color,
    val onSurfaceVariant: Color,
    val surfaceContainer: Color,
    val outlineVariant: Color
) {
    fun applyTo(base: ColorScheme) = base.copy(
        primary = primary,
        onPrimary = Color.White,
        primaryContainer = primaryContainer,
        onPrimaryContainer = onPrimaryContainer,
        secondary = primary,
        secondaryContainer = primaryContainer,
        onSecondaryContainer = onPrimaryContainer,
        background = background,
        onBackground = onSurface,
        surface = surface,
        surfaceTint = primary,
        onSurface = onSurface,
        surfaceVariant = surfaceContainer,
        onSurfaceVariant = onSurfaceVariant,
        outlineVariant = outlineVariant,
        surfaceContainer = surfaceContainer
    )

    companion object {
        private val incoming = MutableStateFlow<PrepdeskAppearance?>(null)
        val current = incoming.asStateFlow()

        fun read(intent: Intent) {
            if (!intent.hasExtra("prepdesk.primary")) return
            fun color(key: String) = Color(intent.getIntExtra("prepdesk.$key", 0))
            incoming.value = PrepdeskAppearance(
                primary = color("primary"), primaryContainer = color("primaryContainer"),
                onPrimaryContainer = color("onPrimaryContainer"), background = color("background"),
                surface = color("surface"), onSurface = color("onSurface"),
                onSurfaceVariant = color("onSurfaceVariant"), surfaceContainer = color("surfaceContainer"),
                outlineVariant = color("outlineVariant")
            )
        }
    }
}
