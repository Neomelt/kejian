package dev.kejian.kejian

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/**
 * School-specific adapter. Login happens in this WebView and is kept by the
 * WebView cookie store; no cookie, password, or page text is logged or sent
 * outside the device.
 */
class UjsWebViewActivity : Activity() {
    private lateinit var webView: WebView
    private lateinit var status: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
        }
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(20, 14, 20, 14)
        }
        status = TextView(this).apply {
            text = "请登录教务系统并打开个人课表"
            setTextColor(Color.DKGRAY)
            setPadding(12, 0, 20, 0)
        }
        val read = Button(this).apply {
            text = "读取课表"
            setOnClickListener { readPage() }
        }
        val close = Button(this).apply {
            text = "返回"
            setOnClickListener { finish() }
        }
        actions.addView(status, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        actions.addView(read)
        actions.addView(close)
        root.addView(actions)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.databaseEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            webViewClient = WebViewClient()
            loadUrl(START_URL)
        }
        root.addView(webView, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }

    private fun readPage() {
        status.text = "正在读取当前页面…"
        webView.evaluateJavascript(EXTRACT_SCRIPT) { encoded ->
            runCatching {
                val raw = JSONTokener(encoded).nextValue() as? String ?: encoded
                val page = JSONObject(raw)
                val cells = mutableListOf<CourseCaptureCell>()
                val rawCells = page.optJSONArray("cells") ?: JSONArray()
                for (index in 0 until rawCells.length()) {
                    val cell = rawCells.optJSONObject(index) ?: continue
                    val children = mutableListOf<String>()
                    val rawChildren = cell.optJSONArray("children")
                    if (rawChildren != null) {
                        for (childIndex in 0 until rawChildren.length()) {
                            rawChildren.optString(childIndex).takeIf { it.isNotBlank() }?.let(children::add)
                        }
                    }
                    cells += CourseCaptureCell(
                        resourceId = cell.optString("id"),
                        text = cell.optString("text"),
                        childTexts = children,
                    )
                }
                val pageText = page.optString("pageText")
                val parsed = CourseCaptureParser.parse(cells, pageText)
                CourseCaptureBridge.emitCapture(
                    mapOf(
                        "sourcePackage" to SOURCE_PACKAGE,
                        "pageTitle" to page.optString("pageTitle", "正方教务系统"),
                        "rawText" to pageText,
                        "cells" to cells.map {
                            mapOf("id" to it.resourceId, "text" to it.text, "children" to it.childTexts)
                        },
                        "courses" to parsed.courses.map { course ->
                            mapOf(
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
                                "credits" to course.credits,
                            )
                        },
                        "diagnostics" to parsed.diagnostics,
                        "activeWeek" to parsed.activeWeek,
                        "capturedAt" to System.currentTimeMillis(),
                    ),
                )
                status.text = "已读取 ${parsed.courses.size} 门课程，请返回课间确认导入"
            }.onFailure { error ->
                status.text = "读取失败：${error.message ?: "页面结构无法识别"}"
            }
        }
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }

    companion object {
        private const val START_URL = "https://jwc.ujs.edu.cn"
        private const val SOURCE_PACKAGE = "dev.kejian.ujs_webview"
        private const val EXTRACT_SCRIPT = """
            (function() {
              const idPattern = /^(?:td_)?[1-7][-_]\d{1,2}/;
              const cells = [];
              const seen = new Set();
              document.querySelectorAll('[id]').forEach(function(el) {
                const id = el.id || '';
                if (!idPattern.test(id)) return;
                const text = (el.innerText || el.textContent || '').trim();
                if (!text || seen.has(id + '|' + text)) return;
                seen.add(id + '|' + text);
                const children = Array.from(el.children)
                  .map(function(child) { return (child.innerText || child.textContent || '').trim(); })
                  .filter(Boolean);
                cells.push({id: id, text: text, children: children});
              });
              return JSON.stringify({
                pageTitle: document.title || '正方教务系统',
                pageText: document.body ? (document.body.innerText || '') : '',
                cells: cells
              });
            })()
        """
    }
}
