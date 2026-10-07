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

    @Test
    fun parsesTdGridCellsWithNestedBlocksWhenThePageOmitsSectionText() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    resourceId = "td_2-9",
                    text = "晚间课程块",
                    childBlocks = listOf(
                        CourseCaptureBlock(
                            title = "嵌入式系统",
                            room = "本部 京江2213",
                            teacher = "甲老师",
                            weeksText = "1-8周",
                            rawText = "嵌入式系统 本部 京江2213 甲老师 1-8周",
                        ),
                        CourseCaptureBlock(
                            title = "自动控制基础",
                            room = "本部 三江0203",
                            teacher = "乙老师",
                            weeksText = "4-14周",
                            rawText = "自动控制基础 本部 三江0203 乙老师 4-14周",
                        ),
                    ),
                ),
                CourseCaptureCell(
                    resourceId = "td_4-10",
                    text = "晚间单课",
                    childBlocks = listOf(
                        CourseCaptureBlock(
                            title = "大学物理",
                            room = "本部 三山503",
                            teacher = "丙老师",
                            weeksText = "1-14周",
                            rawText = "大学物理 本部 三山503 丙老师 1-14周",
                        ),
                    ),
                ),
            ),
            "个人课表 第5周",
        )
        assertEquals(3, result.courses.size)
        assertEquals(listOf(9, 9, 10), result.courses.map { it.startSlot })
        assertEquals(listOf(1, 4, 1), result.courses.map { it.weeks.first() })
        assertEquals(listOf(2, 2, 4), result.courses.map { it.weekday })
        assertEquals("自动控制基础", result.courses[1].title)
        assertEquals("乙老师", result.courses[1].teacher)
    }

    @Test
    fun parsesPlainSingleTd4_9BlockWithSlotFromResourceId() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    resourceId = "td_4-9",
                    text = "大学物理A(II) 本部 三山503 尚老师 1-14周",
                    childBlocks = listOf(
                        CourseCaptureBlock(
                            title = "大学物理A(II)",
                            room = "本部 三山503",
                            teacher = "尚老师",
                            weeksText = "1-14周",
                            rawText = "大学物理A(II) 本部 三山503 尚老师 1-14周",
                        ),
                    ),
                ),
            ),
            "个人课表 第5周",
        )
        assertEquals(1, result.courses.size)
        assertEquals(9, result.courses.single().startSlot)
        assertEquals(4, result.courses.single().weekday)
        assertEquals("大学物理A(II)", result.courses.single().title)
        assertEquals("本部 三山503", result.courses.single().room)
        assertEquals("尚老师", result.courses.single().teacher)
    }

    @Test
    fun parsesPlainTdCellTextWhenAccessibilityHasNoNestedBlocks() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    resourceId = "td_2-9",
                    text = "嵌入式系统 (2026-2027-1)-04530051-04 本部 京江2号楼2213 岳慧裕 1-8周 " +
                        "自动控制基础 (2026-2027-1)-04520033-01 本部 三江楼0203 马世典,高岩 4-14周",
                ),
            ),
            "学生课表查询（按周次） 周次:5",
        )

        assertEquals(2, result.courses.size)
        assertEquals(setOf("嵌入式系统", "自动控制基础"), result.courses.map { it.title }.toSet())
        assertTrue(result.courses.all { it.weekday == 2 && it.startSlot == 9 })
    }

    @Test
    fun keepsPlainRoomTeacherAndCreditsFromRealWecomText() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    resourceId = "td_4-1",
                    text = "汽车节能与环境保护技术 (2026-2027-1)-04530066-01 " +
                        "本部 京江3号楼3504 刘军 (1-2节)9-16周 2.0 必修",
                ),
            ),
            "个人课表 第6周",
        )

        val course = result.courses.single()
        assertEquals("汽车节能与环境保护技术", course.title)
        assertEquals("本部 京江3号楼3504", course.room)
        assertEquals("刘军", course.teacher)
        assertEquals(2.0, course.credits)
        assertEquals(4, course.weekday)
        assertEquals(1, course.startSlot)
        assertEquals(2, course.endSlot)
    }

    @Test
    fun recoversCompactFlattenedFieldsWhenAccessibilityDropsWhitespace() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    resourceId = "4-1",
                    text = "汽车节能与环境保护技术(1-2节)9-16周本部京江3号楼3504刘军" +
                        "(2026-2027-1)-04530066-01车辆2305;车辆23062.0选修",
                ),
            ),
        )
        val course = result.courses.single()
        assertEquals("汽车节能与环境保护技术", course.title)
        assertEquals("本部京江3号楼3504", course.room)
        assertEquals("刘军", course.teacher)
        assertEquals(2.0, course.credits)
        assertEquals(listOf(9, 10, 11, 12, 13, 14, 15, 16), course.weeks)
    }

    @Test
    fun usesReliableSourceSpanOnlyWhenProvided() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    resourceId = "5-9",
                    text = "晚间块 1-8周",
                    slotSpan = 2,
                    childBlocks = listOf(
                        CourseCaptureBlock(
                            title = "晚间课程",
                            room = "教学楼101",
                            teacher = "甲老师",
                            weeksText = "1-8周",
                            rawText = "晚间课程 教学楼101 甲老师 1-8周",
                        ),
                    ),
                ),
            ),
        )
        assertEquals(9, result.courses.single().startSlot)
        assertEquals(10, result.courses.single().endSlot)
    }

    @Test
    fun parsesPrivateUseMetadataMarkersAndCreditWithoutPersonalAssumptions() {
        val result = CourseCaptureParser.parse(
            listOf(
                CourseCaptureCell(
                    resourceId = "4-1",
                    text = "车辆工程" + '\uE023' + "(1-2节)9-16周" +
                        '\uE062' + "本部 教学楼101" + '\uE008' + "甲老师" +
                        '\uE021' + "(2026-2027-1)-12345678-01" +
                        '\uE184' + '\uE184' + "2.0" + '\uE184' + "必修",
                ),
            ),
        )
        val course = result.courses.single()
        assertEquals("车辆工程", course.title)
        assertEquals("本部 教学楼101", course.room)
        assertEquals("甲老师", course.teacher)
        assertEquals(2.0, course.credits)
        assertEquals(listOf(9, 10, 11, 12, 13, 14, 15, 16), course.weeks)
    }
}
