package io.github.thelazyindian.tasks

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity: FlutterFragmentActivity() {
    companion object { @Volatile var isVisible = false }
    override fun onResume() { super.onResume(); isVisible = true }
    override fun onPause() { isVisible = false; super.onPause() }

    private val CHANNEL = "io.github.thelazyindian.tasks/native"
    private val BT_CHANNEL = "io.github.thelazyindian.tasks/bluetooth_permissions"
    private val BT_PERMISSION_REQUEST_CODE = 2001
    private val PICK_SHARE_FILES_REQUEST_CODE = 2002
    private var pendingBluetoothResult: MethodChannel.Result? = null
    private var pendingShareResult: MethodChannel.Result? = null
    private val fileExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val btHandler: (io.flutter.plugin.common.MethodCall, MethodChannel.Result) -> Unit = { call, result ->
            when (call.method) {
                "checkBluetoothPermissions" -> {
                    result.success(hasBluetoothPermissions())
                }
                "requestBluetoothPermissions" -> {
                    requestBluetoothPermissions(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BT_CHANNEL).setMethodCallHandler(btHandler)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getUpdateAbi" -> result.success(Build.SUPPORTED_64_BIT_ABIS.firstOrNull())
                "openBitChat", "shareScheduleInPrepChat" -> {
                    val appearance = call.arguments as? Map<*, *>
                    val chat = Intent()
                        .setClassName(packageName, "com.bitchat.android.MainActivity")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    appearance?.forEach { (key, value) ->
                        if (key is String && value is Number) chat.putExtra("prepdesk.$key", value.toInt())
                    }
                    when (call.method) {
                        "shareScheduleInPrepChat" -> chat.putExtra("prepdesk.destination", "shareSchedule")
                    }
                    startActivity(chat)
                    result.success(null)
                }
                "setAdaptiveColors" -> {
                    getSharedPreferences("nyro_appearance", MODE_PRIVATE).edit()
                        .putBoolean("adaptive", call.argument<Boolean>("enabled") ?: true)
                        .putInt("accent", call.argument<Number>("accent")?.toInt() ?: 0xFF315DA8.toInt()).apply()
                    contentResolver.notifyChange(Uri.parse("content://$packageName.appearance"), null)
                    result.success(null)
                }
                "checkBluetoothPermissions" -> {
                    result.success(hasBluetoothPermissions())
                }
                "requestBluetoothPermissions" -> {
                    requestBluetoothPermissions(result)
                }
                "hasStudyAlarmMigration" -> {
                    result.success(getSharedPreferences("nyro_alarm_setup", MODE_PRIVATE).getBoolean("migrated", false))
                }
                "markStudyAlarmMigration" -> {
                    getSharedPreferences("nyro_alarm_setup", MODE_PRIVATE).edit().putBoolean("migrated", true).apply()
                    result.success(null)
                }
                "scheduleStudyAlarms" -> {
                    try {
                        val alarms = call.argument<List<Map<String, Any>>>("alarms") ?: emptyList()
                        alarms.forEach { value ->
                            io.github.thelazyindian.tasks.alarms.StudyAlarmScheduler.schedule(this, org.json.JSONObject(value))
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("ALARM_SCHEDULE", error.message, null)
                    }
                }
                "cancelStudyAlarmGroup" -> {
                    val group = call.argument<Int>("group")
                    if (group != null) io.github.thelazyindian.tasks.alarms.StudyAlarmScheduler.cancelGroup(this, group)
                    result.success(null)
                }
                "stopStudyAlarm" -> {
                    val id = call.argument<Int>("id")
                    if (id == io.github.thelazyindian.tasks.alarms.StudyAlarmService.activeId) {
                        stopService(Intent(this, io.github.thelazyindian.tasks.alarms.StudyAlarmService::class.java))
                    }
                    result.success(null)
                }
                "setAlarmWindow" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    if (Build.VERSION.SDK_INT >= 27) {
                        setShowWhenLocked(enabled)
                        setTurnScreenOn(enabled)
                    } else if (enabled) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
                    }
                    result.success(null)
                }
                "getNotificationAccess" -> {
                    val alarms = getSystemService(android.content.Context.ALARM_SERVICE) as android.app.AlarmManager
                    val notifications = getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                    val studyImportance = notifications.getNotificationChannel("nyro_study_channel")?.importance
                    result.success(mapOf(
                        "notifications" to androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled(),
                        "studyAlerts" to (studyImportance != android.app.NotificationManager.IMPORTANCE_NONE),
                        "studyHeadsUp" to (studyImportance == null || studyImportance >= android.app.NotificationManager.IMPORTANCE_HIGH),
                        "exact" to (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()),
                        "fullScreen" to (Build.VERSION.SDK_INT < 34 || notifications.canUseFullScreenIntent())
                    ))
                }
                "openStudyNotificationSettings" -> {
                    startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        .putExtra(Settings.EXTRA_CHANNEL_ID, "nyro_study_channel"))
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= 26) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                            Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                "setSecureWindow" -> {
                    if (call.argument<Boolean>("enabled") == true) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                "dismissDeliveredNotification" -> {
                    val id = call.argument<Int>("id")
                    if (id != null) {
                        val manager = getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                        manager.cancel(id)
                    }
                    result.success(null)
                }
                "getAppCacheDir" -> {
                    result.success(cacheDir.absolutePath)
                }
                "getSharedFilesDir" -> {
                    val dir = File(filesDir, "shared_files").apply { mkdirs() }
                    result.success(dir.absolutePath)
                }
                "pickFilesToShare" -> {
                    if (pendingShareResult != null) {
                        result.error("PICKER_BUSY", "A file picker is already active", null)
                    } else {
                        pendingShareResult = result
                        val mimeTypes = call.argument<List<String>>("mimeTypes")
                            ?.map { it.trim() }
                            ?.filter { it.isNotEmpty() }
                            ?: emptyList()
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            if (mimeTypes.size == 1 && mimeTypes[0] != "*/*") {
                                type = mimeTypes[0]
                            } else {
                                type = "*/*"
                                if (mimeTypes.isNotEmpty() && !(mimeTypes.size == 1 && mimeTypes[0] == "*/*")) {
                                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                                }
                            }
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, PICK_SHARE_FILES_REQUEST_CODE)
                    }
                }
                "openSharedFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "File path is empty", null)
                    } else {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "File does not exist", null)
                        } else {
                            try {
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                                val ext = file.extension.lowercase()
                                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
                                val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, mime)
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                                }
                                startActivity(Intent.createChooser(viewIntent, "Open file"))
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("OPEN_ERROR", e.localizedMessage, null)
                            }
                        }
                    }
                }
                "saveSharedFileToDownloads" -> {
                    val filePath = call.argument<String>("filePath")
                    val fileName = call.argument<String>("fileName") ?: "shared_file"
                    if (filePath.isNullOrBlank() || !File(filePath).exists()) {
                        result.error("FILE_NOT_FOUND", "Source file not found", null)
                    } else {
                        fileExecutor.execute {
                            try {
                                val src = File(filePath)
                                val mime = MimeTypeMap.getSingleton()
                                    .getMimeTypeFromExtension(src.extension.lowercase())
                                    ?: "application/octet-stream"
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    val values = ContentValues().apply {
                                        put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                                        put(MediaStore.Downloads.MIME_TYPE, mime)
                                        put(MediaStore.Downloads.IS_PENDING, 1)
                                    }
                                    val resolver = contentResolver
                                    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                        ?: throw IllegalStateException("Could not create Download entry")
                                    resolver.openOutputStream(uri)?.use { out ->
                                        BufferedInputStream(FileInputStream(src), 262144).use { input ->
                                            input.copyTo(out, 262144)
                                        }
                                    }
                                    values.clear()
                                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                                    resolver.update(uri, values, null, null)
                                    runOnUiThread { result.success("Downloads/$fileName") }
                                } else {
                                    val downloads = try {
                                        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).apply { mkdirs() }
                                    } catch (_: Exception) {
                                        (getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir).apply { mkdirs() }
                                    }
                                    var dest = File(downloads, fileName)
                                    if (dest.exists()) {
                                        dest = File(downloads, "${System.currentTimeMillis()}_$fileName")
                                    }
                                    try {
                                        BufferedInputStream(FileInputStream(src), 262144).use { input ->
                                            BufferedOutputStream(FileOutputStream(dest), 262144).use { out ->
                                                input.copyTo(out, 262144)
                                            }
                                        }
                                    } catch (_: Exception) {
                                        val fallbackDir = (getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: filesDir).apply { mkdirs() }
                                        dest = File(fallbackDir, dest.name)
                                        BufferedInputStream(FileInputStream(src), 262144).use { input ->
                                            BufferedOutputStream(FileOutputStream(dest), 262144).use { out ->
                                                input.copyTo(out, 262144)
                                            }
                                        }
                                    }
                                    runOnUiThread { result.success(dest.absolutePath) }
                                }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SAVE_ERROR", e.localizedMessage, null) }
                            }
                        }
                    }
                }
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallUnknownAppsSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                            data = Uri.parse("package:$packageName")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "APK path is empty", null)
                    } else {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                        } else {
                            try {
                                val contentUri = FileProvider.getUriForFile(
                                    this,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(contentUri, "application/vnd.android.package-archive")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_ERROR", e.localizedMessage, null)
                            }
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val scan = ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
            val advertise = ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
            val connect = ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
            scan && advertise && connect
        } else {
            val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
            fine || coarse
        }
    }

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        if (hasBluetoothPermissions()) {
            result.success(true)
            return
        }
        pendingBluetoothResult = result
        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )
        }
        ActivityCompat.requestPermissions(this, perms, BT_PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BT_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingBluetoothResult?.success(granted)
            pendingBluetoothResult = null
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_SHARE_FILES_REQUEST_CODE) return
        val callback = pendingShareResult ?: return
        pendingShareResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(emptyList<Map<String, Any>>())
            return
        }

        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) {
                clip.getItemAt(i).uri?.let { uris.add(it) }
            }
        }
        if (uris.isEmpty()) {
            data.data?.let { uris.add(it) }
        }
        if (uris.isEmpty()) {
            callback.success(emptyList<Map<String, Any>>())
            return
        }

        val shareDir = File(filesDir, "shared_files").apply { mkdirs() }
        fileExecutor.execute {
            val copied = mutableListOf<Map<String, Any>>()
            for (uri in uris) {
                try {
                    val name = queryDisplayName(uri)
                    val target = uniqueDestinationFile(shareDir, name)
                    contentResolver.openInputStream(uri)?.use { input ->
                        BufferedInputStream(input, 262144).use { bufIn ->
                            BufferedOutputStream(FileOutputStream(target), 262144).use { bufOut ->
                                bufIn.copyTo(bufOut, 262144)
                            }
                        }
                    }
                    if (target.exists()) {
                        copied.add(
                            mapOf(
                                "name" to name,
                                "path" to target.absolutePath,
                                "size" to target.length()
                            )
                        )
                    }
                } catch (_: Exception) {
                }
            }
            runOnUiThread { callback.success(copied) }
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        var displayName = "shared_${System.currentTimeMillis()}"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) {
                    val value = cursor.getString(idx)
                    if (!value.isNullOrBlank()) displayName = value
                }
            }
        }
        val clean = displayName.replace('\\', '/').substringAfterLast('/')
            .replace(Regex("[\\x00-\\x1F\\x7F<>:\"|?*]"), "_").trim()
        return if (clean.isEmpty() || clean == "." || clean == "..") {
            "shared_${System.currentTimeMillis()}"
        } else {
            clean
        }
    }

    private fun uniqueDestinationFile(dir: File, cleanName: String): File {
        val dot = cleanName.lastIndexOf('.')
        val base = if (dot > 0) cleanName.substring(0, dot) else cleanName
        val ext = if (dot > 0) cleanName.substring(dot) else ""
        var candidate = File(dir, cleanName)
        var suffix = 1
        while (candidate.exists()) {
            candidate = File(dir, "$base ($suffix)$ext")
            suffix++
        }
        return candidate
    }
}
