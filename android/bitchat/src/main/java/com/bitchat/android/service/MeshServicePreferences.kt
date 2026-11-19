package com.bitchat.android.service

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.content.SharedPreferences

object MeshServicePreferences {
    private const val PREFS_NAME = "bitchat_mesh_service_prefs"
    private const val KEY_AUTO_START = "auto_start_on_boot"
    private const val KEY_BACKGROUND_ENABLED = "background_enabled"

    private lateinit var context: Context
    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        this.context = context.applicationContext
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun isAutoStartEnabled(default: Boolean = false): Boolean {
        return prefs.getBoolean(KEY_AUTO_START, default)
    }

    fun setAutoStartEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_AUTO_START, enabled).apply()
        context.packageManager.setComponentEnabledSetting(
            ComponentName(context, BootCompletedReceiver::class.java),
            if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
    }

    fun isBackgroundEnabled(default: Boolean = false): Boolean {
        return prefs.getBoolean(KEY_BACKGROUND_ENABLED, default)
    }

    fun setBackgroundEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_BACKGROUND_ENABLED, enabled).apply()
    }
}
