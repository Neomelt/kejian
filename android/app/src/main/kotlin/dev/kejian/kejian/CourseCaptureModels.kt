package dev.kejian.kejian

import android.view.accessibility.AccessibilityNodeInfo
import android.graphics.Rect
import java.security.MessageDigest
import java.util.Locale

/** A small, platform-neutral snapshot of one visible accessibility cell. */
data class CourseCaptureCell(
    val resourceId: String,
    val text: String,
    /** Direct TextView children are the authoritative title list for cells
     * containing two or more courses (the page concatenates their metadata). */
    val childTexts: List<String> = emptyList(),
    /** Flattened metadata blocks for the newer `td_D-S` grid. */
    val childBlocks: List<CourseCaptureBlock> = emptyList(),
)

data class CourseCaptureBlock(
    val title: String,
    val room: String,
    val teacher: String,
    val weeksText: String,
    val rawText: String,
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
            val (cellWeekday, cellSlot) = parseResourceId(cell.resourceId)
            if (!normalized.contains("节") && cell.childBlocks.isEmpty() &&
                (cellWeekday == null || cellSlot == null)
            ) {
                if (normalized.contains("周")) {
                    diagnostics += "无法识别课程单元格：${cell.text}"
                }
                return@forEach
            }

            val segments = splitCourseSegments(normalized)
            val blockSegments = if (!normalized.contains(COURSE_MARKER) && cell.childBlocks.isNotEmpty()) {
                cell.childBlocks.map { block ->
                    // Keep the block's structured fields alongside its raw
                    // text; the parser below uses these when no E023 marker
                    // is exposed by the newer WebView.
                    block.rawText
                }
            } else {
                emptyList()
            }
            val parseSegments = if (blockSegments.isNotEmpty()) {
                blockSegments
            } else if (normalized.contains(COURSE_MARKER)) {
                segments
            } else {
                splitPlainCourseSegments(normalized)
            }
            parseSegments.forEachIndexed { segmentIndex, segment ->
                val block = cell.childBlocks.getOrNull(segmentIndex)
                val slot = slotPattern.find(segment)
                val weeks = parseWeeks(
                    block?.weeksText?.takeIf { it.isNotBlank() } ?: segment,
                )
                val (weekday, resourceSlot) = cellWeekday to cellSlot
                if ((slot == null && resourceSlot == null) || weeks.first.isEmpty()) {
                    diagnostics += "无法识别课程单元格：${cell.text}"
                    return@forEachIndexed
                }
                val start = slot?.let { match ->
                    match.groupValues[1].ifBlank { match.groupValues[3] }.toIntOrNull()
                } ?: resourceSlot
                val end = slot?.let { match ->
                    match.groupValues[2].ifBlank { match.groupValues[3] }.toIntOrNull()
                } ?: resourceSlot
                val titleEnd = slot?.range?.first
                val code = courseCodePattern.find(segment)
                val fallbackTitle = segment.substring(0, titleEnd ?: code?.range?.first ?: segment.length)
                val title = block?.title?.takeIf { it.isNotBlank() }
                    ?: cell.childTexts.getOrNull(segmentIndex)
                    ?.takeIf { it.isNotBlank() }
                    ?: fallbackTitle
                        .trim(' ', '\t', '-', '—', ':', '：', '(', '（', COURSE_MARKER)
                        .ifBlank { "未命名课程" }
                val effectiveStart = start
                val effectiveEnd = end
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
                    teacher = block?.teacher?.takeIf { it.isNotBlank() }
                        ?: markerValue(segment, '\uE008', '\uE021')
                        .ifBlank { labelValue(teacherPattern, segment) },
                    room = block?.room?.takeIf { it.isNotBlank() }
                        ?: markerValue(segment, '\uE062', '\uE008')
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
        val weekdayCenters = mutableMapOf<Int, Int>()
        val slotTops = mutableMapOf<Int, Int>()

        fun collectGeometry(node: AccessibilityNodeInfo?) {
            if (node == null) return
            val text = node.text?.toString()?.trim().orEmpty()
            val bounds = Rect().also(node::getBoundsInScreen)
            Regex("周([一二三四五六日天])").find(text)?.groupValues?.getOrNull(1)?.firstOrNull()?.let {
                val weekday = "一二三四五六日天".indexOf(it).let { index -> if (index >= 7) 7 else index + 1 }
                weekdayCenters[weekday] = bounds.centerX()
            }
            Regex("^(\\d{1,2})\\s+\\d{2}:\\d{2}:\\d{2}").find(text)
                ?.groupValues?.getOrNull(1)?.toIntOrNull()?.let { slotTops[it] = bounds.top }
            for (index in 0 until node.childCount) collectGeometry(node.getChild(index))
        }
        collectGeometry(root)

        fun geometryId(node: AccessibilityNodeInfo): String {
            if (weekdayCenters.isEmpty() || slotTops.isEmpty()) return ""
            val bounds = Rect().also(node::getBoundsInScreen)
            val weekday = weekdayCenters.minByOrNull { (_, center) -> kotlin.math.abs(center - bounds.centerX()) }?.key
            val slot = slotTops.filterValues { it <= bounds.top }.maxByOrNull { it.value }?.key
            return if (weekday != null && slot != null) "$weekday-$slot" else ""
        }
        fun leafTexts(node: AccessibilityNodeInfo): List<String> {
            val own = node.text?.toString()?.trim().orEmpty()
            if (node.childCount == 0) return own.takeIf { it.isNotBlank() }?.let(::listOf) ?: emptyList()
            val descendants = (0 until node.childCount).flatMap { index ->
                node.getChild(index)?.let(::leafTexts) ?: emptyList()
            }
            return if (descendants.isNotEmpty()) descendants
            else own.takeIf { it.isNotBlank() }?.let(::listOf) ?: emptyList()
        }

        fun courseBlock(node: AccessibilityNodeInfo): CourseCaptureBlock? {
            val leaves = leafTexts(node)
            if (leaves.isEmpty()) return null
            val title = leaves.first()
            val weeks = leaves.firstOrNull { weekPattern.containsMatchIn(it) }.orEmpty()
            val room = leaves.drop(1).firstOrNull {
                it.contains("楼") || it.contains("教室") || it.contains("体育馆") || it.contains("场")
            } ?: leaves.getOrNull(2).orEmpty()
            val teacher = leaves.drop(1).firstOrNull {
                it != room && !it.startsWith("(") && !it.contains("周")
            } ?: leaves.getOrNull(3).orEmpty()
            return CourseCaptureBlock(
                title = title,
                room = room,
                teacher = teacher,
                weeksText = weeks,
                rawText = leaves.joinToString(" "),
            )
        }

        fun visit(node: AccessibilityNodeInfo?) {
            if (node == null) return
            val text = node.text?.toString()?.trim().orEmpty()
            val rawId = node.viewIdResourceName?.substringAfterLast(":id/").orEmpty()
            if (text.isNotBlank()) {
                texts += text
                val hasGridId = Regex(
                    "^(?:[^/]+/)?(?:td_)?[1-7][-_]\\d{1,2}(?:[^0-9].*)?$",
                ).containsMatchIn(rawId)
                val hasCourseShape = text.contains("节") && text.contains("周")
                // A WebView may expose both a grid cell and its parent as text.
                // Prefer the identified grid cell; accept id-less text only when
                // it looks like exactly one course rather than a whole table.
                val looksLikeOneCourse = hasCourseShape &&
                    text.count { it == '节' } == 1 && text.count { it == '周' } >= 1
                val id = if (hasGridId) rawId else if (looksLikeOneCourse) geometryId(node) else ""
                val key = "$id|$text"
                if (seen.add(key) && (hasGridId || looksLikeOneCourse)) {
                    val childBlocks = if (hasGridId) {
                        (0 until node.childCount).mapNotNull { index ->
                            node.getChild(index)?.let(::courseBlock)
                        }
                    } else {
                        emptyList()
                    }
                    cells += CourseCaptureCell(
                        resourceId = id,
                        text = text,
                        childTexts = childBlocks.map { it.title },
                        childBlocks = childBlocks,
                    )
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
        val match = Regex(
            "^(?:[^/]+/)?(?:td_)?([1-7])[-_](\\d{1,2})(?:[^0-9].*)?$",
        ).find(resourceId)
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

    private fun splitPlainCourseSegments(text: String): List<String> {
        val codes = courseCodePattern.findAll(text).toList()
        if (codes.size <= 1) return listOf(text)
        val starts = codes.drop(1).mapNotNull { code ->
            weekPattern.findAll(text.substring(0, code.range.first)).lastOrNull()?.range?.last?.plus(1)
        }
        if (starts.size != codes.size - 1) return listOf(text)
        val boundaries = listOf(0) + starts + listOf(text.length)
        return boundaries.zipWithNext().map { (start, end) -> text.substring(start, end).trim() }
    }

    private fun markerValue(text: String, startMarker: Char, endMarker: Char): String {
        val start = text.indexOf(startMarker)
        if (start < 0) return ""
        val valueStart = start + 1
        val end = text.indexOf(endMarker, valueStart).takeIf { it >= 0 } ?: text.length
        return text.substring(valueStart, end).trim()
    }

    private val courseCodePattern = Regex("\\(\\d{4}-\\d{4}-\\d\\)-[A-Za-z0-9-]+")

    private fun stableId(resourceId: String, text: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("$resourceId|$text".toByteArray(Charsets.UTF_8))
        return bytes.take(12).joinToString("") { "%02x".format(Locale.ROOT, it) }
    }

    private const val COURSE_MARKER = '\uE023'
}
