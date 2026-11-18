package io.github.thelazyindian.tasks

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    companion object { @Volatile var isVisible = false }
    override fun onResume() { super.onResume(); isVisible = true }
    override fun onPause() { isVisible = false; super.onPause() }

    private val CHANNEL = "io.github.thelazyindian.tasks/native"
    private val BT_CHANNEL = "io.github.thelazyindian.tasks/bluetooth_permissions"
    private val BT_PERMISSION_REQUEST_CODE = 2001
    private var pendingBluetoothResult: MethodChannel.Result? = null

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
                "setAdaptiveColors" -> {
                    getSharedPreferences("nyro_appearance", MODE_PRIVATE).edit()
                        .putBoolean("adaptive", call.argument<Boolean>("enabled") ?: true).apply()
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
                    result.success(mapOf(
                        "notifications" to androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled(),
                        "exact" to (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()),
                        "fullScreen" to (Build.VERSION.SDK_INT < 34 || notifications.canUseFullScreenIntent())
                    ))
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
}
