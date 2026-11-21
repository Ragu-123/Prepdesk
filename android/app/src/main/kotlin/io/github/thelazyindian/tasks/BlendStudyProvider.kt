package io.github.thelazyindian.tasks

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Read-only, same-app access to the fields a user can preview in Blend. */
class BlendStudyProvider : ContentProvider() {
    override fun onCreate() = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        if (method != "studyDay" || callingPackage != context?.packageName) return null
        val day = runCatching { LocalDate.parse(arg) }.getOrNull() ?: return null
        val app = context ?: return null
        val file = File(app.getDir("flutter", 0), "nyro_local.db")
        if (!file.isFile) return null
        return runCatching {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                val items = JSONArray()
                val categories = listOf(
                    listOf("Schedule", "lectures", "topic", "date_str"),
                    listOf("Revisits", "revisit_items", "topic", "due_date"),
                    listOf("Quizzes", "quiz_items", "title", "date_str")
                )
                val dateValues = arrayOf(day.toString(),
                    day.format(DateTimeFormatter.ofPattern("dd MMM uuuu", Locale.ENGLISH)),
                    day.format(DateTimeFormatter.ofPattern("d MMM uuuu", Locale.ENGLISH)))
                for ((category, table, title, dateColumn) in categories) {
                    db.rawQuery(
                        "SELECT id, $title, status FROM $table WHERE trim($dateColumn) COLLATE NOCASE IN (?, ?, ?) ORDER BY id",
                        dateValues
                    ).use { row ->
                        while (row.moveToNext()) {
                            val label = row.getString(1)?.trim().orEmpty()
                            if (label.isBlank()) continue
                            items.put(JSONObject()
                                .put("id", "$category:${row.getLong(0)}")
                                .put("title", label.take(100))
                                .put("category", category)
                                .put("day", day.toString())
                                .put("done", row.getString(2)?.uppercase() in setOf("COMPLETED", "DONE")))
                        }
                    }
                }
                Bundle().apply { putString("items", items.toString()) }
            }
        }.getOrNull()
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = 0
}
