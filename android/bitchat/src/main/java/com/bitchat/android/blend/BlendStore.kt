package com.bitchat.android.blend

import android.content.Context
import android.util.Base64
import com.bitchat.android.services.AndroidConversationStorageCipher
import org.json.JSONArray
import org.json.JSONObject

internal data class BlendSession(
    val id: String,
    val peer: String,
    val mode: BlendMode,
    val owner: Boolean,
    val role: BlendRole = BlendRole.SPECTATOR,
    val peerRole: BlendRole = BlendRole.SPECTATOR,
    val active: Boolean = false,
    val stopped: Boolean = false,
    val automaticAt: String? = null,
    val categories: Set<String> = BlendProtocol.categories.toSet(),
    val tasks: List<BlendItem> = emptyList(),
    val mineDone: Set<String> = emptySet(),
    val theirs: List<BlendItem> = emptyList(),
    val receivedAt: Long = 0,
    val remoteRevision: Long = 0,
    val scheduledDay: String = "",
    val requested: Boolean = false
) {
    fun json() = JSONObject().put("id", id).put("peer", peer).put("mode", mode.name)
        .put("owner", owner).put("role", role.name).put("peerRole", peerRole.name)
        .put("active", active).put("stopped", stopped).put("auto", automaticAt)
        .put("categories", JSONArray(categories.toList())).put("tasks", BlendProtocol.pack(tasks))
        .put("mine", JSONArray(mineDone.toList())).put("theirs", BlendProtocol.pack(theirs))
        .put("receivedAt", receivedAt).put("remoteRevision", remoteRevision)
        .put("scheduledDay", scheduledDay).put("requested", requested)

    companion object {
        fun parse(row: JSONObject) = BlendSession(
            id = row.getString("id"), peer = row.getString("peer"), mode = BlendMode.valueOf(row.getString("mode")),
            owner = row.getBoolean("owner"), role = BlendRole.valueOf(row.getString("role")),
            peerRole = BlendRole.valueOf(row.getString("peerRole")), active = row.optBoolean("active"),
            stopped = row.optBoolean("stopped"), automaticAt = row.optString("auto").takeIf { it.isNotBlank() },
            categories = row.optJSONArray("categories").strings().toSet(), tasks = BlendProtocol.items(row.optJSONArray("tasks")),
            mineDone = row.optJSONArray("mine").strings().toSet(), theirs = BlendProtocol.items(row.optJSONArray("theirs")),
            receivedAt = row.optLong("receivedAt"), remoteRevision = row.optLong("remoteRevision"),
            scheduledDay = row.optString("scheduledDay"), requested = row.optBoolean("requested")
        )
    }
}

internal fun JSONArray?.strings(): List<String> =
    if (this == null) emptyList() else (0 until length()).map { optString(it) }

internal class BlendStore(context: Context) {
    private val preferences = context.getSharedPreferences("prepchat_blend", Context.MODE_PRIVATE)
    private val cipher = AndroidConversationStorageCipher("prepchat_blend_storage_v1")
    private val aad = "prepchat-blend-v1".toByteArray()

    fun read(): JSONObject {
        val value = preferences.getString("state", null) ?: return JSONObject()
        return JSONObject(cipher.decrypt(Base64.decode(value, Base64.NO_WRAP), aad).toString(Charsets.UTF_8))
    }

    fun write(value: JSONObject) {
        val bytes = cipher.encrypt(value.toString().toByteArray(), aad)
        check(preferences.edit().putString("state", Base64.encodeToString(bytes, Base64.NO_WRAP)).commit())
    }
}
