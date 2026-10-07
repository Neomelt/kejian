package dev.kejian.kejian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CourseCaptureParserTest {
    @Test
    fun parsesSlotWeekTeacherRoomAndGridPosition() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    "1-1",
                    "高等数学 (1-2节)1-8周 教室：J01 教师：张老师",
                ),
            ),
            "个人课表 第3周",
        )
        assertEquals(1, result.courses.size)
        val course = result.courses.single()
        assertEquals("高等数学", course.title)
        assertEquals("张老师", course.teacher)
        assertEquals("J01", course.room)
        assertEquals(1, course.weekday)
        assertEquals(1, course.startSlot)
        assertEquals(2, course.endSlot)
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7, 8), course.weeks)
        assertTrue(course.inActiveWeek == true)
    }

    @Test
    fun marksRetakeLikeSameGridSlotAsDuplicateGroup() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell("3-1", "英语 (3-4节)1-16周 教室：A101 教师：甲"),
                CourseCaptureCell("3-1b", "重修英语 (3-4节)1-16周 教室：A102 教师：乙"),
            ),
            "个人课表 第5周",
        )
        assertEquals(2, result.courses.size)
        assertEquals(
            result.courses[0].duplicateGroupKey,
            result.courses[1].duplicateGroupKey,
        )
        assertTrue(result.courses.all { it.inActiveWeek == true })
    }

    @Test
    fun parsesOddAndEvenWeeksAndLeavesUnparseableCellInDiagnostics() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell("2-2", "物理 (2节)2-10周(双) 教室：B201"),
                CourseCaptureCell("2-3", "待确认课程 (3节)"),
            ),
            "个人课表 第3周",
        )
        assertEquals("even", result.courses.single().parity)
        assertEquals(listOf(2, 4, 6, 8, 10), result.courses.single().weeks)
        assertEquals(false, result.courses.single().inActiveWeek)
        assertEquals(1, result.diagnostics.size)
    }

    @Test
    fun splitsTwoCoursesConcatenatedInOneGridCellUsingChildTitlesAndMarkers() {
        val marker = '\uE023'
        val location = '\uE062'
        val teacher = '\uE008'
        val code = '\uE021'
        val text =
            "智能汽车与自动驾驶 $marker (1-2节)1-8周 $location 本部 京江3504 $teacher 张老师 $code CODE-1 $code 必修 " +
                "汽车节能与环境保护技术 $marker (1-2节)9-16周 $location 本部 京江3504 $teacher 李老师 $code CODE-2 $code 选修"
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    "4-1",
                    text,
                    childTexts = listOf("智能汽车与自动驾驶", "汽车节能与环境保护技术"),
                ),
            ),
            "个人课表 第3周",
        )
        assertEquals(2, result.courses.size)
        assertEquals("智能汽车与自动驾驶", result.courses[0].title)
        assertEquals("张老师", result.courses[0].teacher)
        assertEquals("本部 京江3504", result.courses[0].room)
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7, 8), result.courses[0].weeks)
        assertEquals("汽车节能与环境保护技术", result.courses[1].title)
        assertEquals("李老师", result.courses[1].teacher)
        assertEquals(listOf(9, 10, 11, 12, 13, 14, 15, 16), result.courses[1].weeks)
        assertEquals(result.courses[0].duplicateGroupKey, result.courses[1].duplicateGroupKey)
    }

    @Test
    fun ignoresOtherCourseGroupNoticeWhenNoReliableSlotExists() {
        val result = CourseCaptureParser.parse(
            cells = emptyList(),
            pageText = "个人课表 第3周 其它课程 课设安排",
        )

        assertTrue(result.courses.isEmpty())
        assertTrue(result.diagnostics.isEmpty())
    }
}
