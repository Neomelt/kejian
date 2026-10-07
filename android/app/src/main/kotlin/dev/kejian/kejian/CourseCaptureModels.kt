package dev.kejian.kejian

import android.view.accessibility.AccessibilityNodeInfo
import java.security.MessageDigest
import java.util.Locale

/** A small, platform-neutral snapshot of one visible accessibility cell. */
data class CourseCaptureCell(
    val resourceId: String,
    val text: String,
    /** Direct TextView children are the authoritative title list for cells
     * containing two or more courses (the page concatenates their metadata). */
    val childTexts: List<String> = emptyList(),
)

data class CapturedCourse(
    val id: String,
    val sourceNodeId: String,
    val rawText: String,
    val title: String,
    val teacher: String,
    val room: String,
    val weekday: Int?,
    val startSlot: Int?,
    val endSlot: Int?,
    val weeks: List<Int>,
    val parity: String,
    val duplicateGroupKey: String?,
    val inActiveWeek: Boolean?,
)

data class CourseParseResult(
    val courses: List<CapturedCourse>,
    val diagnostics: List<String>,
    val activeWeek: Int?,
)

/**
 * Parser for the text exposed by the current Jiangsu University/enterprise-WeChat
 * page.  It is intentionally conservative: an item that does not contain a
 * recognisable slot and week expression is reported as a diagnostic instead of
 * being guessed into the schedule.
 */
object CourseCaptureParser {
    private val slotPattern = Regex(
        "(?:第\\s*)?(\\d{1,2})\\s*[-~至到]\\s*(\\d{1,2})\\s*节"
            + "|(?:第\\s*)?(\\d{1,2})\\s*节"
    )
    private val weekPattern = Regex("(\\d{1,2})\\s*[-~至到]\\s*(\\d{1,2})\\s*周")
    private val singleWeekPattern = Regex("(?<![\\d-])(\\d{1,2})\\s*周")
    private val teacherPattern = Regex(
        "(?:任课)?教师\\s*[:：]?\\s*([^\\n;；|]+?)(?=\\s+(?:教室|地点|教师|周)|$)",
    )
    private val roomPattern = Regex(
        "(?:上课)?(?:教室|地点)\\s*[:：]?\\s*([^\\n;；|]+?)(?=\\s+(?:任课)?教师|\\s+周|$)",
    )
    private val activeWeekPatterns = listOf(
        Regex("当前(?:周次|周)\\s*[:：]?\\s*(\\d{1,2})\\s*周?"),
        Regex("第\\s*(\\d{1,2})\\s*周"),
    )

    fun parse(cells: List<CourseCaptureCell>, pageText: String = ""): CourseParseResult {
        val activeWeek = extractActiveWeek(pageText)
        val diagnostics = mutableListOf<String>()
        val courses = mutableListOf<CapturedCourse>()
        val seen = mutableSetOf<String>()

        cells.forEach { cell ->
            val normalized = normalize(cell.text)
            if (normalized.isBlank()) return@forEach
            val dedupeKey = "${cell.resourceId}|$normalized"
            if (!seen.add(dedupeKey)) return@forEach
            if (!normalized.contains("节") || !normalized.contains("周")) {
                if (normalized.contains("节") || normalized.contains("周")) {
                    diagnostics += "无法识别课程单元格：${cell.text}"
                }
                return@forEach
            }

            val segments = splitCourseSegments(normalized)
            segments.forEachIndexed { segmentIndex, segment ->
                val slot = slotPattern.find(segment)
                val weeks = parseWeeks(segment)
                if (slot == null || weeks.first.isEmpty()) {
                    diagnostics += "无法识别课程单元格：${cell.text}"
                    return@forEachIndexed
                }
                val start = slot.groupValues[1].ifBlank { slot.groupValues[3] }.toInt()
                val end = slot.groupValues[2].ifBlank { slot.groupValues[3] }.toInt()
                val titleEnd = slot.range.first
                val fallbackTitle = segment.substring(0, titleEnd)
                val title = cell.childTexts.getOrNull(segmentIndex)
                    ?.takeIf { it.isNotBlank() }
                    ?: fallbackTitle
                        .trim(' ', '\t', '-', '—', ':', '：', '(', '（', COURSE_MARKER)
                        .ifBlank { "未命名课程" }
                val (weekday, resourceSlot) = parseResourceId(cell.resourceId)
                val effectiveStart = start.takeIf { it > 0 } ?: resourceSlot
                val effectiveEnd = end.takeIf { it > 0 } ?: resourceSlot
                val parity = weeks.second
                val filteredWeeks = weeks.first.filter { week ->
                    parity == "all" || (parity == "odd" && week % 2 == 1) ||
                        (parity == "even" && week % 2 == 0)
                }
                val inActiveWeek = activeWeek?.let { week ->
                    filteredWeeks.contains(week)
                }
                val groupKey = if (weekday != null && effectiveStart != null && effectiveEnd != null) {
                    "$weekday:$effectiveStart:$effectiveEnd"
                } else {
                    null
                }
                courses += CapturedCourse(
                    id = stableId(cell.resourceId, "$segmentIndex|$segment"),
                    sourceNodeId = cell.resourceId,
                    rawText = segment,
                    title = title,
                    teacher = markerValue(segment, '\uE008', '\uE021')
                        .ifBlank { labelValue(teacherPattern, segment) },
                    room = markerValue(segment, '\uE062', '\uE008')
                        .ifBlank { labelValue(roomPattern, segment) },
                    weekday = weekday,
                    startSlot = effectiveStart,
                    endSlot = effectiveEnd,
                    weeks = filteredWeeks,
                    parity = parity,
                    duplicateGroupKey = groupKey,
                    inActiveWeek = inActiveWeek,
                )
            }
        }

        val duplicateCounts = courses.groupingBy { it.duplicateGroupKey }.eachCount()
        val withGroup = courses.map { course ->
            if (course.duplicateGroupKey != null &&
                (duplicateCounts[course.duplicateGroupKey] ?: 0) > 1
            ) course else course.copy(duplicateGroupKey = null)
        }
        return CourseParseResult(withGroup, diagnostics, activeWeek)
    }

    /** Convenience adapter used by tests and by callers that only have a node tree. */
    fun snapshot(root: AccessibilityNodeInfo): Pair<String, List<CourseCaptureCell>> {
        val cells = mutableListOf<CourseCaptureCell>()
        val texts = mutableListOf<String>()
        val seen = mutableSetOf<String>()
        fun visit(node: AccessibilityNodeInfo?) {
            if (node == null) return
            val text = node.text?.toString()?.trim().orEmpty()
            val id = node.viewIdResourceName?.substringAfterLast(":id/").orEmpty()
            if (text.isNotBlank()) {
                texts += text
                val key = "$id|$text"
                val hasCourseShape = text.contains("节") && text.contains("周")
                val hasGridId = Regex("^(?:[^/]+/)?[1-7][-_]\\d{1,2}").containsMatchIn(id)
                // A WebView may expose both a grid cell and its parent as text.
                // Prefer the identified grid cell; accept id-less text only when
                // it looks like exactly one course rather than a whole table.
                val looksLikeOneCourse = hasCourseShape &&
                    text.count { it == '节' } == 1 && text.count { it == '周' } >= 1
                if (seen.add(key) && (hasGridId || looksLikeOneCourse)) {
                    val childTexts = if (hasGridId) {
                        (0 until node.childCount).mapNotNull { index ->
                            node.getChild(index)?.text?.toString()?.trim()
                                ?.takeIf { it.isNotBlank() }
                        }
                    } else {
                        emptyList()
                    }
                    cells += CourseCaptureCell(id, text, childTexts)
                }
            }
            for (i in 0 until node.childCount) visit(node.getChild(i))
        }
        visit(root)
        return texts.distinct().joinToString(" ") to cells
    }

    private fun normalize(value: String): String = value
        .replace('（', '(')
        .replace('）', ')')
        .replace(Regex("[\\r\\n\\t]+"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun parseWeeks(text: String): Pair<List<Int>, String> {
        val values = linkedSetOf<Int>()
        weekPattern.findAll(text).forEach { match ->
            val start = match.groupValues[1].toInt()
            val end = match.groupValues[2].toInt()
            if (end >= start && end - start <= 64) {
                (start..end).forEach { values.add(it) }
            }
        }
        if (values.isEmpty()) singleWeekPattern.findAll(text).forEach {
            values += it.groupValues[1].toInt()
        }
        val parity = when {
            Regex("双周|\\(\\s*双\\s*\\)").containsMatchIn(text) -> "even"
            Regex("单周|\\(\\s*单\\s*\\)").containsMatchIn(text) -> "odd"
            else -> "all"
        }
        return values.sorted() to parity
    }

    private fun extractActiveWeek(pageText: String): Int? = activeWeekPatterns
        .asSequence()
        .mapNotNull { it.find(pageText)?.groupValues?.getOrNull(1)?.toIntOrNull() }
        .firstOrNull { it in 1..64 }

    private fun parseResourceId(resourceId: String): Pair<Int?, Int?> {
        // Some WebView grids suffix duplicate cells (for example `3-1b`),
        // so accept a non-numeric suffix after the weekday/slot pair.
        val match = Regex("^(?:[^/]+/)?([1-7])[-_](\\d{1,2})(?:[^0-9].*)?$").find(resourceId)
            ?: return null to null
        return match.groupValues[1].toInt() to match.groupValues[2].toInt()
    }

    private fun labelValue(pattern: Regex, text: String): String =
        pattern.find(text)?.groupValues?.getOrNull(1)?.trim().orEmpty()

    private fun splitCourseSegments(text: String): List<String> {
        if (!text.contains(COURSE_MARKER)) return listOf(text)
        return text.split(COURSE_MARKER)
            .drop(1)
            .map { "$COURSE_MARKER$it" }
    }

    private fun markerValue(text: String, startMarker: Char, endMarker: Char): String {
        val start = text.indexOf(startMarker)
        if (start < 0) return ""
        val valueStart = start + 1
        val end = text.indexOf(endMarker, valueStart).takeIf { it >= 0 } ?: text.length
        return text.substring(valueStart, end).trim()
    }

    private fun stableId(resourceId: String, text: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("$resourceId|$text".toByteArray(Charsets.UTF_8))
        return bytes.take(12).joinToString("") { "%02x".format(Locale.ROOT, it) }
    }

    private const val COURSE_MARKER = '\uE023'
}
