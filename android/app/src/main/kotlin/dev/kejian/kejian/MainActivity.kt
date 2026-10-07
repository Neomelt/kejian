package dev.kejian.kejian

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var courseCaptureChannel: MethodChannel? = null
    private var appUpdateChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(
                NotificationChannel(
                    ReminderReceiver.CHANNEL_ID,
                    "课程提醒",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "课程开始前的本地提醒" }
            )
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permission" -> requestNotificationPermission(result)
                    "status" -> result.success(status())
                    "schedule" -> result.success(schedule(call.argument<List<Any?>>("reminders")))
                    "cancel" -> result.success(cancel())
                    else -> result.notImplemented()
                }
            }
        courseCaptureChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CourseCaptureBridge.CHANNEL,
        ).also { channel ->
            CourseCaptureBridge.attach(channel)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        CourseCaptureBridge.markListenerReady()
                        result.success(CourseCaptureBridge.consumePending())
                    }
                    "status" -> result.success(
                        mapOf(
                            "accessibilityEnabled" to
                                CourseCaptureAccessibilityService.isAccessibilityEnabled(this),
                            "overlayEnabled" to
                                (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                                    Settings.canDrawOverlays(this)),
                            "targetPackage" to CourseCaptureAccessibilityService.TARGET_PACKAGE,
                        ),
                    )
                    "openAccessibilitySettings" -> {
                        startActivity(CourseCaptureAccessibilityService.accessibilityIntent(this))
                        result.success(true)
                    }
                    "openOverlaySettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            startActivity(CourseCaptureAccessibilityService.overlayIntent(this))
                        }
                        result.success(true)
                    }
                    "capture" -> {
                        val service = CourseCaptureAccessibilityService.current()
                        if (service == null) {
                            result.error(
                                "accessibility_unavailable",
                                "请先在系统设置中启用课间的辅助功能服务",
                                null,
                            )
                        } else {
                            result.success(service.captureAndEmit())
                        }
                    }
                    "openTargetApp" -> {
                        val launch = packageManager.getLaunchIntentForPackage(
                            CourseCaptureAccessibilityService.TARGET_PACKAGE,
                        )
                        if (launch == null) {
                            result.error("target_app_missing", "未找到企业微信", null)
                        } else {
                            startActivity(launch)
                            result.success(true)
                        }
                    }
                    "openUjsAdapter" -> {
                        val intent = Intent(this, UjsWebViewActivity::class.java)
                        call.argument<String>("startUrl")?.trim()?.takeIf { it.isNotEmpty() }
                            ?.let { intent.putExtra(UjsWebViewActivity.EXTRA_START_URL, it) }
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        appUpdateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_UPDATE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "appInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(
                            mapOf(
                                "packageName" to packageName,
                                "versionName" to (info.versionName ?: ""),
                                "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    info.longVersionCode
                                } else {
                                    @Suppress("DEPRECATION") info.versionCode.toLong()
                                },
                            ),
                        )
                    }
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        courseCaptureChannel?.let(CourseCaptureBridge::detach)
        courseCaptureChannel = null
        appUpdateChannel = null
        super.onDestroy()
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("invalid_apk", "没有可安装的 APK", null)
            return
        }
        val apk = File(path)
        if (!apk.isFile || !apk.canRead()) {
            result.error("invalid_apk", "找不到已校验的 APK", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            result.error("install_permission", "请允许课间安装未知应用后再点击安装", null)
            return
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
        result.success(true)
    }

    private fun isAuthorized(): Boolean = Build.VERSION.SDK_INT < 33 ||
        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || isAuthorized()) {
            result.success(true)
            return
        }
        permissionResult?.error("permission_pending", "A permission request is already active", null)
        permissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            val result = permissionResult
            permissionResult = null
            result?.success(isAuthorized())
        }
    }

    private fun status(): Map<String, Any> {
        val prefs = getSharedPreferences(ReminderReceiver.PREFS, MODE_PRIVATE)
        val array = runCatching { JSONArray(prefs.getString(ReminderReceiver.KEY_ITEMS, "[]")) }.getOrDefault(JSONArray())
        var pending = 0
        val now = System.currentTimeMillis()
        for (i in 0 until array.length()) if ((array.optJSONObject(i)?.optLong("timestamp", 0L) ?: 0L) > now) pending++
        return mapOf("authorized" to isAuthorized(), "pending" to pending, "supported" to true)
    }

    private fun schedule(raw: List<Any?>?): Int {
        val reminders = raw ?: emptyList()
        cancel()
        val result = JSONArray()
        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        reminders.forEach { value ->
            val map = value as? Map<*, *> ?: return@forEach
            val id = (map["id"] as? Number)?.toInt() ?: return@forEach
            val timestamp = (map["timestamp"] as? Number)?.toLong() ?: return@forEach
            if (timestamp <= now) return@forEach
            val title = map["title"]?.toString().orEmpty()
            val body = map["body"]?.toString().orEmpty()
            val item = JSONObject().apply {
                put("id", id)
                put("title", title)
                put("body", body)
                put("timestamp", timestamp)
            }
            result.put(item)
            val pending = ReminderReceiver.alarmIntent(this, id, title, body)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pending)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, timestamp, pending)
            }
        }
        getSharedPreferences(ReminderReceiver.PREFS, MODE_PRIVATE).edit()
            .putString(ReminderReceiver.KEY_ITEMS, result.toString()).apply()
        return result.length()
    }

    private fun cancel(): Boolean {
        val prefs = getSharedPreferences(ReminderReceiver.PREFS, MODE_PRIVATE)
        val array = runCatching { JSONArray(prefs.getString(ReminderReceiver.KEY_ITEMS, "[]")) }.getOrDefault(JSONArray())
        val ids = buildList {
            for (i in 0 until array.length()) array.optJSONObject(i)?.optInt("id")?.let(::add)
        }
        ReminderReceiver.cancelAll(this, ids)
        prefs.edit().putString(ReminderReceiver.KEY_ITEMS, "[]").apply()
        return true
    }

    companion object {
        private const val CHANNEL = "dev.kejian/reminders"
        private const val APP_UPDATE_CHANNEL = "dev.kejian/app_update"
        private const val PERMISSION_REQUEST = 4107
    }
}
