package com.bitchat.android.blend

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

internal data class BlendItem(
    val id: String, val title: String, val category: String, val day: String, val done: Boolean
) {
    fun json() = JSONObject().put("id", id).put("title", title).put("category", category)
        .put("day", day).put("done", done)
}

internal enum class BlendMode(val label: String) {
    TIMETABLE("Compare timetables"), CHECKLIST("Shared checklist")
}

internal enum class BlendRole(val label: String) {
    PARTICIPATE("Participate"), SPECTATOR("Watch only")
}

internal enum class BlendEvent(val description: String) {
    SCHEDULE("Shared a Prepdesk schedule"),
    INVITE("Invited you to a Blend"),
    ACCEPT("Accepted the Blend"),
    PLAN("Updated the shared checklist"),
    PROGRESS("Shared study progress"),
    REQUEST("Requested a progress update"),
    STOP("Ended the Blend"),
    CHECK_IN("Sent a study check-in")
}

internal data class BlendFrame(
    val event: BlendEvent,
    val blend: String,
    val data: JSONObject = JSONObject()
)

internal object BlendProtocol {
    private const val Marker = "\nprepdesk-blend/1 "
    internal const val MaxBytes = 3_500
    const val MaxItems = 24
    val categories = listOf("Schedule", "Revisits", "Quizzes")

    fun hasMarker(text: String): Boolean = Marker in text

    fun encode(frame: BlendFrame): String {
        val bytes = JSONObject().put("event", frame.event.name).put("blend", frame.blend)
            .put("data", frame.data).toString().toByteArray()
        val text = "${frame.event.description}. Open in PrepChat.$Marker" +
            Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
        require(text.toByteArray().size <= MaxBytes) { "Select fewer study items to send." }
        return text
    }

    fun decode(text: String): BlendFrame? {
        if (text.length > MaxBytes || !hasMarker(text)) return null
        return runCatching {
            val json = JSONObject(String(Base64.decode(text.substringAfter(Marker), Base64.URL_SAFE), Charsets.UTF_8))
            val id = json.getString("blend")
            require(id.length in 16..64 && id.all { it.isLetterOrDigit() || it == '-' })
            BlendFrame(BlendEvent.valueOf(json.getString("event")), id, json.getJSONObject("data"))
        }.getOrNull()
    }

    fun items(array: JSONArray?, limit: Int = MaxItems): List<BlendItem> {
        if (array == null || array.length() > limit) return emptyList()
        return (0 until array.length()).mapNotNull { i ->
            runCatching {
                val row = array.getJSONObject(i)
                val category = row.getString("category")
                val title = row.getString("title").trim()
                val id = row.getString("id")
                require(category in categories && title.length in 1..100 && id.length in 1..64)
                BlendItem(id, title, category, LocalDate.parse(row.getString("day")).toString(), row.getBoolean("done"))
            }.getOrNull()
        }.distinctBy { it.id }
    }

    fun pack(items: List<BlendItem>) = JSONArray().apply { items.forEach { put(it.json()) } }
}
