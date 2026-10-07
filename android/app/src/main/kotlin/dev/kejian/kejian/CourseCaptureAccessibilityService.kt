package dev.kejian.kejian

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Toast

/**
 * Reads the user-visible course grid in enterprise WeChat after an explicit
 * tap on the overlay button. It never observes network traffic or credentials.
 */
class CourseCaptureAccessibilityService : AccessibilityService() {
    private var windowManager: WindowManager? = null
    private var overlay: View? = null
    /** Keep the last target-app tree because tapping the overlay can briefly
     * move the active window to this app before the capture callback runs. */
    private var latestTargetRoot: AccessibilityNodeInfo? = null
    private val captureHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            notificationTimeout = 100
            flags = flags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // The latest root is read only after the user taps the overlay or the
        // Flutter button. Do not capture silently on every content change.
        // If the user granted overlay permission after enabling the service,
        // the next target-app event is a safe point to install the button.
        if (event?.packageName?.toString() == TARGET_PACKAGE) {
            rootInActiveWindow?.let { root ->
                latestTargetRoot?.recycle()
                latestTargetRoot = AccessibilityNodeInfo.obtain(root)
            }
            if (overlay == null) showOverlayIfAllowed()
        } else {
            removeOverlay()
        }
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        removeOverlay()
        latestTargetRoot?.recycle()
        latestTargetRoot = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun captureAndEmit(): Boolean {
        // Let the current WebView finish publishing its accessibility tree;
        // the overlay click itself can momentarily become the active window.
        captureHandler.postDelayed({ captureNow() }, 350L)
        return true
    }

    private fun captureNow(): Boolean {
        val current = rootInActiveWindow?.let(AccessibilityNodeInfo::obtain)
        val cached = latestTargetRoot?.let(AccessibilityNodeInfo::obtain)
        var root = when {
            current?.packageName?.toString() == TARGET_PACKAGE &&
                cached?.packageName?.toString() == TARGET_PACKAGE -> current
            current?.packageName?.toString() == TARGET_PACKAGE -> current
            cached?.packageName?.toString() == TARGET_PACKAGE -> {
                current?.recycle()
                cached
            }
            else -> {
                current?.recycle()
                cached
            }
        } ?: run {
            notifyUser("未找到当前页面")
            return false
        }
        if (current != null && cached != null &&
            current.packageName?.toString() == TARGET_PACKAGE &&
            cached.packageName?.toString() == TARGET_PACKAGE
        ) {
            val currentCells = CourseCaptureParser.snapshot(current).second.size
            val cachedCells = CourseCaptureParser.snapshot(cached).second.size
            if (currentCells >= cachedCells) {
                cached.recycle()
                root = current
            } else {
                current.recycle()
                root = cached
            }
        }
        val packageName = root.packageName?.toString().orEmpty()
        if (packageName != TARGET_PACKAGE) {
            root.recycle()
            notifyUser("请先打开企业微信中的个人课表")
            return false
        }
        val (pageText, cells) = CourseCaptureParser.snapshot(root)
        Log.i(TAG, "capture package=$packageName pageText=${pageText.length} cells=${cells.size}")
        val title = findPageTitle(pageText)
        if (!isSchedulePage(pageText, cells)) {
            root.recycle()
            notifyUser("当前页面不是个人课表")
            return false
        }
        val parsed = CourseCaptureParser.parse(cells, pageText)
        val courseMaps = parsed.courses.map { course ->
            mapOf<String, Any?>(
                "id" to course.id,
                "sourceNodeId" to course.sourceNodeId,
                "rawText" to course.rawText,
                "title" to course.title,
                "teacher" to course.teacher,
                "room" to course.room,
                "weekday" to course.weekday,
                "startSlot" to course.startSlot,
                "endSlot" to course.endSlot,
                "weeks" to course.weeks,
                "parity" to course.parity,
                "duplicateGroupKey" to course.duplicateGroupKey,
                "inActiveWeek" to course.inActiveWeek,
            )
        }
        val cellMaps = cells.map {
            mapOf(
                "id" to it.resourceId,
                "text" to it.text,
                "children" to it.childTexts,
            )
        }
        CourseCaptureBridge.emitCapture(
            mapOf(
                "sourcePackage" to packageName,
                "pageTitle" to title,
                "rawText" to pageText,
                "cells" to cellMaps,
                "courses" to courseMaps,
                "diagnostics" to parsed.diagnostics,
                "activeWeek" to parsed.activeWeek,
                "capturedAt" to System.currentTimeMillis(),
            ),
        )
        root.recycle()
        notifyUser("已读取 ${courseMaps.size} 门课程，请回到课间确认导入", long = true)
        return true
    }

    private fun showOverlayIfAllowed() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) return
        if (overlay != null) return
        val button = Button(this).apply {
            text = "读取课表"
            setOnClickListener {
                isEnabled = false
                text = "读取中…"
                val success = captureAndEmit()
                isEnabled = true
                text = if (success) "读取完成" else "读取课表"
                if (success) {
                    Handler(Looper.getMainLooper()).postDelayed(
                        { if (overlay != null) text = "读取课表" },
                        3500L,
                    )
                }
            }
            alpha = 0.94f
            contentDescription = "读取企业微信课表"
        }
        val stop = Button(this).apply {
            text = "停止"
            setOnClickListener {
                removeOverlay()
                disableSelf()
            }
            alpha = 0.94f
            contentDescription = "停止读取企业微信课表"
        }
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(button)
            addView(stop)
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 12
            y = 160
        }
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        runCatching { windowManager?.addView(container, params) }
            .onSuccess { overlay = container }
            .onFailure { notifyUser("悬浮窗权限未开启") }
    }

    private fun removeOverlay() {
        val current = overlay ?: return
        runCatching { windowManager?.removeView(current) }
        overlay = null
    }

    @Suppress("DEPRECATION")
    private fun overlayWindowType(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    } else {
        WindowManager.LayoutParams.TYPE_PHONE
    }

    private fun findPageTitle(pageText: String): String {
        val title = Regex("个人课表|我的课表|课表").find(pageText)?.value
        return title ?: "企业微信课表"
    }

    private fun isSchedulePage(pageText: String, cells: List<CourseCaptureCell>): Boolean {
        val hasTitle = pageText.contains("课表")
        val hasWeeks = pageText.contains("周")
        val hasExplicitSlots = pageText.contains("节")
        val hasGridCells = cells.any {
            Regex("^(?:[^/]+/)?(?:td_)?[1-7][-_]\\d{1,2}").containsMatchIn(it.resourceId)
        }
        return hasTitle && hasWeeks && (hasExplicitSlots || hasGridCells)
    }

    private fun notifyUser(message: String, long: Boolean = false) {
        Toast.makeText(this, message, if (long) Toast.LENGTH_LONG else Toast.LENGTH_SHORT).show()
    }

    companion object {
        const val TARGET_PACKAGE = "com.tencent.wework"
        private const val TAG = "KejianCapture"
        @Volatile private var instance: CourseCaptureAccessibilityService? = null

        fun current(): CourseCaptureAccessibilityService? = instance

        fun accessibilityIntent(context: Context): Intent =
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)

        fun overlayIntent(context: Context): Intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            android.net.Uri.parse("package:${context.packageName}"),
        )

        fun isAccessibilityEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val expected = "${context.packageName}/${CourseCaptureAccessibilityService::class.java.name}"
            return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
        }
    }
}
