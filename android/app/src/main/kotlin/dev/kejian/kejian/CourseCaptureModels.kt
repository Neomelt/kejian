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
    /** Number of individual timetable rows spanned by this source cell.
     * Callers must supply this only when the source exposes a reliable span. */
    val slotSpan: Int = 1,
)

data class CourseCaptureBlock(
    val title: String,
    val room: String,
    val teacher: String,
    val weeksText: String,
    val rawText: String,
    val credits: Double? = null,
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
    val credits: Double?,
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
    private val weekExpressionPattern = Regex(
        "(?<![\\d-])(\\d{1,2}(?:\\s*[-~至到]\\s*\\d{1,2})?" +
            "(?:\\s*[,，、]\\s*\\d{1,2}(?:\\s*[-~至到]\\s*\\d{1,2})?)*)\\s*周",
    )
    private val courseNaturePattern = Regex("(?:必修|选修|任选|限选|公选|通选)")
    private val privateUsePattern = Regex("[\\uE000-\\uF8FF]")
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

            val blocks = cell.childBlocks.filter { block ->
                block.rawText.isNotBlank() &&
                    parseWeeks(block.weeksText.ifBlank { block.rawText }).first.isNotEmpty()
            }
            // Only align structured blocks when they describe the whole cell.
            // A decorative child or a single parent containing several courses
            // must never shift the metadata onto a different course segment.
            val useBlocks = blocks.isNotEmpty() &&
                (!normalized.contains(COURSE_MARKER) ||
                    blocks.size == normalized.count { it == COURSE_MARKER })
            val parseSegments = if (useBlocks) {
                blocks.map { normalize(it.rawText) }
            } else if (normalized.contains(COURSE_MARKER)) {
                splitCourseSegments(normalized, cell.childTexts)
            } else {
                splitPlainCourseSegments(normalized)
            }
            parseSegments.forEachIndexed { segmentIndex, segment ->
                val block = if (useBlocks) blocks.getOrNull(segmentIndex) else null
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
                } ?: resourceSlot?.let { it + cell.slotSpan.coerceAtLeast(1) - 1 }
                if (start == null || end == null || start < 1 || end < start) {
                    diagnostics += "无法识别课程节次：${cell.text}"
                    return@forEachIndexed
                }
                val title = sequenceOf(
                    block?.title,
                    cell.childTexts.getOrNull(segmentIndex),
                    segment,
                ).filterNotNull().map(::courseTitle).firstOrNull { it.isNotBlank() }
                    ?: "未命名课程"
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
                val groupKey = weekday?.let { "$it:$effectiveStart:$effectiveEnd" }
                courses += CapturedCourse(
                    id = stableId(cell.resourceId, "$segmentIndex|$segment"),
                    sourceNodeId = cell.resourceId,
                    rawText = segment,
                    title = title,
                    teacher = cleanMetadata(block?.teacher.orEmpty()).takeIf { it.isNotBlank() }
                        ?: markerValue(segment, TEACHER_MARKER)
                        .ifBlank { labelValue(teacherPattern, segment) }
                        .ifBlank { plainMetadata(segment).second },
                    room = cleanMetadata(block?.room.orEmpty()).takeIf { it.isNotBlank() }
                        ?: markerValue(segment, ROOM_MARKER)
                        .ifBlank { labelValue(roomPattern, segment) }
                        .ifBlank { plainMetadata(segment).first },
                    weekday = weekday,
                    startSlot = effectiveStart,
                    endSlot = effectiveEnd,
                    weeks = filteredWeeks,
                    parity = parity,
                    duplicateGroupKey = groupKey,
                    inActiveWeek = inActiveWeek,
                    credits = block?.credits ?: parseCredits(segment),
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
            val raw = normalize(leaves.joinToString(" "))
            if (parseWeeks(raw).first.isEmpty() || raw.count { it == COURSE_MARKER } > 1) {
                return null
            }
            val title = courseTitle(leaves.first())
            val plain = plainMetadata(raw)
            // Missing metadata stays missing. Positional fallbacks such as
            // leaves[2]/leaves[3] can mistake a time or a week for room/teacher.
            val room = markerValue(raw, ROOM_MARKER)
                .ifBlank { labelValue(roomPattern, raw) }
                .ifBlank { plain.first }
            val teacher = markerValue(raw, TEACHER_MARKER)
                .ifBlank { labelValue(teacherPattern, raw) }
                .ifBlank { plain.second }
            return CourseCaptureBlock(
                title = title,
                room = cleanMetadata(room),
                teacher = cleanMetadata(teacher),
                weeksText = raw,
                rawText = raw,
                credits = parseCredits(raw),
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
        weekExpressionPattern.findAll(text).forEach { match ->
            match.groupValues[1].split(Regex("[,，、]")).forEach { part ->
                val bounds = part.trim().split(Regex("[-~至到]")).map { it.trim().toInt() }
                val start = bounds.first()
                val end = bounds.last()
                if (start in 1..64 && end in start..64) {
                    (start..end).forEach { values.add(it) }
                }
            }
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

    private fun courseTitle(text: String): String {
        val normalized = normalize(text)
        val end = listOfNotNull(
            normalized.indexOf(COURSE_MARKER).takeIf { it >= 0 },
            courseCodePattern.find(normalized)?.range?.first,
            slotPattern.find(normalized)?.range?.first,
        ).minOrNull() ?: normalized.length
        return normalized.substring(0, end)
            .trim(' ', '\t', '-', '—', ':', '：', '(', '（')
    }

    private fun splitCourseSegments(text: String, childTitles: List<String>): List<String> {
        if (!text.contains(COURSE_MARKER)) return listOf(text)
        val markers = text.indices.filter { text[it] == COURSE_MARKER }
        // The icon occurs AFTER the title. Splitting at it loses that title
        // and appends the following title to the preceding course's metadata.
        val starts = mutableListOf(0)
        markers.drop(1).forEachIndexed { index, marker ->
            val previousMarker = markers[index]
            val prefix = text.substring(previousMarker + 1, marker)
            val childTitle = childTitles.getOrNull(index + 1)?.let(::courseTitle)
                ?.takeIf { it.isNotBlank() }
            val titleStart = childTitle?.let { text.lastIndexOf(it, marker - 1) }
                ?.takeIf { it > previousMarker }
                ?: courseNaturePattern.findAll(prefix).lastOrNull()?.range?.last?.let {
                    previousMarker + 1 + it + 1
                }
            // Without a reliable field boundary keep the text intact rather
            // than borrowing a neighboring course's weeks or teacher.
            if (titleStart == null) return listOf(text)
            starts += titleStart
        }
        return (starts + text.length).zipWithNext().map { (start, end) ->
            text.substring(start, end).trim()
        }
    }

    private fun splitPlainCourseSegments(text: String): List<String> {
        val codes = courseCodePattern.findAll(text).toList()
        if (codes.size <= 1) return listOf(text)
        val starts = codes.zipWithNext().mapNotNull { (previousCode, nextCode) ->
            val metadata = text.substring(previousCode.range.last + 1, nextCode.range.first)
            val week = weekExpressionPattern.findAll(metadata).lastOrNull() ?: return@mapNotNull null
            val weekEnd = week.range.last + 1
            val trailing = metadata.substring(weekEnd)
            val natureEnd = courseNaturePattern.find(trailing)?.range?.last?.plus(1)
            val parityEnd = Regex("^\\s*\\(?[单双]\\)?(?:周)?")
                .find(trailing)?.range?.last?.plus(1) ?: 0
            previousCode.range.last + 1 + weekEnd + (natureEnd ?: parityEnd)
        }
        if (starts.size != codes.size - 1) return listOf(text)
        val boundaries = listOf(0) + starts + listOf(text.length)
        return boundaries.zipWithNext().map { (start, end) -> text.substring(start, end).trim() }
    }

    private fun markerValue(text: String, startMarker: Char): String {
        val start = text.indexOf(startMarker)
        if (start < 0) return ""
        val valueStart = start + 1
        val end = privateUsePattern.find(text, valueStart)?.range?.first ?: text.length
        return cleanMetadata(text.substring(valueStart, end))
    }

    private fun parseCredits(text: String): Double? {
        val normalized = text.replace(privateUsePattern, " ")
        val labeled = Regex("(?:课程)?学分\\s*[:：]?\\s*(\\d+(?:\\.\\d+)?)")
            .find(normalized)?.groupValues?.getOrNull(1)?.toDoubleOrNull()
        if (labeled != null) return labeled
        // In compact accessibility text, a decimal credit value may touch the
        // class code immediately before it (e.g. “车辆23062.0选修”). Decimal
        // matching avoids treating the trailing class number as credits.
        val compactDecimal = Regex("([0-9]\\.[0-9]+)(?=\\s*(?:必修|选修|任选|限选|公选|通选))")
            .find(normalized)?.groupValues?.getOrNull(1)?.toDoubleOrNull()
        if (compactDecimal != null) return compactDecimal
        return Regex("(?:^|\\s|[)）])([0-9]+(?:\\.[0-9]+)?)\\s*(?:必修|选修|任选|限选|公选|通选)(?:\\s|$)")
            .find(normalized)?.groupValues?.getOrNull(1)?.toDoubleOrNull()
    }

    private fun cleanMetadata(value: String): String = value
        .replace(privateUsePattern, " ")
        .replace(Regex("^(?:上课地点|地点|教室|任课教师|教师)\\s*[:：]?\\s*"), "")
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun plainMetadata(text: String): Pair<String, String> {
        val code = courseCodePattern.find(text) ?: return "" to ""
        val week = weekExpressionPattern.find(text) ?: return "" to ""
        val middle = if (week.range.last < code.range.first) {
            text.substring(week.range.last + 1, code.range.first)
        } else if (code.range.last < week.range.first) {
            text.substring(code.range.last + 1, week.range.first)
        } else {
            return "" to ""
        }
        val cleaned = middle
            .replace(Regex("\\([^)]*节\\)"), " ")
            .replace(slotPattern, " ")
            .replace(privateUsePattern, " ")
            .let(::cleanMetadata)
        if (cleaned.isBlank()) return "" to ""
        val roomMatch = Regex("^(.*(?:楼|教室|体育馆|场)[0-9A-Za-z()（）号-]*)(.*)$")
            .find(cleaned)
        if (roomMatch != null) {
            return roomMatch.groupValues[1].trim() to roomMatch.groupValues[2].trim()
        }
        val split = Regex("^(.*)\\s+([^\\s]+)$").find(cleaned)
            ?: return cleaned to ""
        return split.groupValues[1].trim() to split.groupValues[2].trim()
    }

    private val courseCodePattern = Regex("\\(\\d{4}-\\d{4}-\\d\\)-[A-Za-z0-9-]+")

    private fun stableId(resourceId: String, text: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest("$resourceId|$text".toByteArray(Charsets.UTF_8))
        return bytes.take(12).joinToString("") { "%02x".format(Locale.ROOT, it) }
    }

    private const val COURSE_MARKER = '\uE023'
    private const val ROOM_MARKER = '\uE062'
    private const val TEACHER_MARKER = '\uE008'
}
