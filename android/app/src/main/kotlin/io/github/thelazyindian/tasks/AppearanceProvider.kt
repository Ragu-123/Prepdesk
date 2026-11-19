package io.github.thelazyindian.tasks

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Bundle

/** Serves the current accent to the chat process under the same app UID. */
class AppearanceProvider : ContentProvider() {
    override fun onCreate() = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        if (method != "notificationStyle") return super.call(method, arg, extras)
        val preferences = context?.getSharedPreferences("nyro_appearance", Context.MODE_PRIVATE)
            ?: return null
        return Bundle().apply {
            putInt("accent", preferences.getInt("accent", 0xFF315DA8.toInt()))
        }
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
