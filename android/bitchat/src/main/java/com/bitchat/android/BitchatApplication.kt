package com.bitchat.android

import android.app.Application
import android.content.Context
import com.bitchat.android.nostr.RelayDirectory
import com.bitchat.android.ui.theme.ThemePreferenceManager
import com.bitchat.android.net.ArtiTorManager

/**
 * Main application class for bitchat Android
 */
internal object BitchatRuntime {
    private var initialized = false

    @Synchronized
    fun initialize(context: Context) {
        if (initialized) return
        val application = context.applicationContext as Application

        // Start the single process-wide power policy before transport components are constructed.
        com.bitchat.android.mesh.PowerManager.getInstance(application).start()

        // Initialize Tor first so any early network goes over Tor
        try {
            val torProvider = ArtiTorManager.getInstance()
            torProvider.init(application)
        } catch (_: Exception){}

        // Initialize relay directory (loads assets/nostr_relays.csv)
        RelayDirectory.initialize(application)

        // Initialize LocationNotesManager dependencies early so sheet subscriptions can start immediately
        try { com.bitchat.android.nostr.LocationNotesInitializer.initialize(application) } catch (_: Exception) { }

        // Initialize favorites persistence early so MessageRouter/NostrTransport can use it on startup
        try {
            com.bitchat.android.favorites.FavoritesPersistenceService.initialize(application)
        } catch (_: Exception) { }

        // Restore private conversations before background transports can deliver new messages.
        // AppStateStore merges any in-flight arrivals by message ID, so startup cannot replace
        // newer transport state with an older database snapshot.
        try {
            com.bitchat.android.services.AppStateStore.initializeConversationPersistence(application)
        } catch (_: Exception) { }

        // Warm up Nostr identity to ensure npub is available for favorite notifications
        try {
            com.bitchat.android.nostr.NostrIdentityBridge.getCurrentNostrIdentity(application)
        } catch (_: Exception) { }

        // Restore the spam filter toggle before transports start admitting public messages
        com.bitchat.android.spam.SpamFilterPreferences.init(application)

        // Initialize theme preference
        ThemePreferenceManager.init(application)

        // Initialize chat UI mode (matrix transcript vs bubbles)
        com.bitchat.android.ui.theme.ChatUiModeManager.init(application)

        // Initialize debug preference manager (persists debug toggles)
        try { com.bitchat.android.ui.debug.DebugPreferenceManager.init(application) } catch (_: Exception) { }

        // Initialize Wi‑Fi Aware controller with persisted default
        try {
            val enabled = com.bitchat.android.ui.debug.DebugPreferenceManager.getWifiAwareEnabled(false)
            com.bitchat.android.wifiaware.WifiAwareController.initialize(application, enabled)
        } catch (_: Exception) { }

        // Initialize Geohash Registries for persistence
        try {
            com.bitchat.android.nostr.GeohashAliasRegistry.initialize(application)
            com.bitchat.android.nostr.GeohashConversationRegistry.initialize(application)
        } catch (_: Exception) { }

        // Own relay connectivity, selected-channel subscriptions, and presence scheduling at the
        // process level so closing the Activity does not disconnect Nostr.
        try { com.bitchat.android.nostr.NostrBackgroundRuntime.initialize(application) } catch (_: Exception) { }

        // Initialize mesh service preferences
        try { com.bitchat.android.service.MeshServicePreferences.init(application) } catch (_: Exception) { }

        initialized = true
    }
}
