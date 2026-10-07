package dev.kejian.kejian

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Process-local bridge between the AccessibilityService and Flutter.
 *
 * The service can outlive the Flutter activity. Captures made while the
 * activity is stopped are retained in memory and delivered after the Dart
 * listener performs the ready/consume handshake. No page text is written to
 * disk by this bridge.
 */
object CourseCaptureBridge {
    const val CHANNEL = "dev.kejian/course_capture"
    const val EVENT_CAPTURE_RESULT = "captureResult"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastCapture: Map<String, Any?>? = null
    private var listenerReady = false
    private var channel: MethodChannel? = null

    @Synchronized
    fun attach(newChannel: MethodChannel) {
        channel = newChannel
        listenerReady = false
    }

    @Synchronized
    fun detach(detached: MethodChannel) {
        if (channel === detached) {
            channel = null
            listenerReady = false
        }
    }

    fun emitCapture(payload: Map<String, Any?>) {
        synchronized(this) {
            // Keep the latest result until Dart explicitly consumes it. This
            // covers a capture made while the Flutter activity is stopped or
            // while its method handler is still being installed.
            lastCapture = payload
            if (channel == null || !listenerReady) return
            // The active Dart listener receives this event immediately; keep
            // the queue only for captures made before the listener was ready.
            lastCapture = null
        }
        sendNow(payload)
    }

    @Synchronized
    fun markListenerReady(): Map<String, Any?>? {
        listenerReady = true
        return lastCapture
    }

    @Synchronized
    fun consumePending(): Map<String, Any?>? {
        val capture = lastCapture
        lastCapture = null
        return capture
    }

    private fun sendNow(payload: Map<String, Any?>) {
        mainHandler.post {
            synchronized(this) {
                channel?.invokeMethod(EVENT_CAPTURE_RESULT, payload)
            }
        }
    }
}
