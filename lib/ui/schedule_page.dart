import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../domain/models.dart' as model;
import '../domain/schedule_helpers.dart';
import '../importing/parsers.dart';
import 'app_theme.dart';
import 'settings_page.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.controller});
  final ScheduleController controller;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  bool dayView = false;

  @override
  Widget build(BuildContext context) {
    final term = widget.controller.activeTerm;
    if (term == null) {
      return EmptySchedule(
        onCreate: () => showTermEditor(context, widget.controller),
        onSample: widget.controller.loadSample,
      );
    }
    final monday = mondayOf(widget.controller.focusedDate);
    final week = currentWeek(term, monday);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 300) return;
        widget.controller.shiftWeek(velocity < 0 ? 1 : -1);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
        children: [
          _ScheduleHeader(
            term: term,
            week: week,
            dayView: dayView,
            onToggle: () => setState(() => dayView = !dayView),
            onAdd: () => showCourseEditor(context, widget.controller, term),
          ),
          const SizedBox(height: 14),
          _WeekControls(
            controller: widget.controller,
            term: term,
            monday: monday,
            week: week,
          ),
          const SizedBox(height: 12),
          _TodayBanner(controller: widget.controller, term: term),
          const SizedBox(height: 18),
          dayView
              ? DaySchedule(
                  controller: widget.controller,
                  term: term,
                  date: model.dateOnly(widget.controller.focusedDate),
                )
              : WeekGrid(
                  controller: widget.controller,
                  term: term,
                  monday: monday,
                ),
        ],
      ),
    );
  }
}

class EmptySchedule extends StatelessWidget {
  const EmptySchedule(
      {super.key, required this.onCreate, required this.onSample});
  final VoidCallback onCreate;
  final Future<void> Function() onSample;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(Icons.calendar_today_rounded,
                  size: 38, color: scheme.primary),
            ),
            const SizedBox(height: 22),
            Text('先把学期放进来',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              '创建一个学期后，可以手动添加课程，或从教务系统导出的文件导入。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('创建学期')),
            const SizedBox(height: 10),
            TextButton.icon(
                onPressed: onSample,
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('先看看示例课表')),
          ],
        ),
      ),
    );
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader(
      {required this.term,
      required this.week,
      required this.dayView,
      required this.onToggle,
      required this.onAdd});
  final model.Term term;
  final int week;
  final bool dayView;
  final VoidCallback onToggle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('课间',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -1)),
                const SizedBox(height: 4),
                Text('${term.name}  ·  第 ${week.clamp(1, term.weekCount)} 周',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton.filledTonal(
              onPressed: onToggle,
              tooltip: dayView ? '周视图' : '日视图',
              icon: Icon(dayView
                  ? Icons.calendar_view_week_outlined
                  : Icons.view_day_outlined)),
          const SizedBox(width: 5),
          IconButton.filled(
              onPressed: onAdd, tooltip: '添加课程', icon: const Icon(Icons.add)),
        ],
      );
}

class _WeekControls extends StatelessWidget {
  const _WeekControls(
      {required this.controller,
      required this.term,
      required this.monday,
      required this.week});
  final ScheduleController controller;
  final model.Term term;
  final DateTime monday;
  final int week;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          IconButton(
              onPressed: () => controller.shiftWeek(-1),
              tooltip: '上一周',
              icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _pickWeek(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(children: [
                  Text(dateRange(monday),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('点击选择周次',
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant))
                ]),
              ),
            ),
          ),
          IconButton(
              onPressed: () => controller.shiftWeek(1),
              tooltip: '下一周',
              icon: const Icon(Icons.chevron_right_rounded)),
          TextButton(
              onPressed: controller.goToCurrentWeek, child: const Text('今天')),
        ],
      );

  Future<void> _pickWeek(BuildContext context) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择周次'),
        children: [
          for (var week = 1; week <= term.weekCount; week++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, week),
              child: Text('第 $week 周',
                  style: TextStyle(
                      fontWeight: week == this.week
                          ? FontWeight.w700
                          : FontWeight.normal)),
            ),
        ],
      ),
    );
    if (selected != null) {
      controller.setFocusedDate(
          term.startMonday.add(Duration(days: (selected - 1) * 7)));
    }
  }
}

class _TodayBanner extends StatelessWidget {
  const _TodayBanner({required this.controller, required this.term});
  final ScheduleController controller;
  final model.Term term;

  @override
  Widget build(BuildContext context) {
    final today = model.dateOnly(DateTime.now());
    final lessons = occurrencesForDate(controller.data, today);
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final next = lessons.where((lesson) {
      final slot = term.slots
          .where((item) => item.index == lesson.startSlot)
          .firstOrNull;
      return slot != null && slot.startMinutes > nowMinutes;
    }).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: .72),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('今天 · ${weekdayName(today.weekday)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      lessons.isEmpty
                          ? '没有课程，留一点时间给自己'
                          : next == null
                              ? '今天有 ${lessons.length} 节课'
                              : '下一节：${next.course.title} · 第 ${next.startSlot} 节',
                      style: Theme.of(context).textTheme.bodySmall)
                ])),
            if (currentWeek(term, today) >= 1 &&
                currentWeek(term, today) <= term.weekCount)
              Text('第 ${currentWeek(term, today)} 周',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }
}

class WeekGrid extends StatelessWidget {
  const WeekGrid(
      {super.key,
      required this.controller,
      required this.term,
      required this.monday});
  final ScheduleController controller;
  final model.Term term;
  final DateTime monday;
  static const periodWidth = 38.0;
  static const dayWidth = 46.0;
  static const rowHeight = 61.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 36;
    final contentWidth = math.max(width, periodWidth + dayWidth * 7);
    final colors = Theme.of(context).colorScheme;
    final slots = term.slots;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: contentWidth,
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(children: [
                const SizedBox(width: periodWidth),
                for (var i = 0; i < 7; i++)
                  Expanded(
                      child: _DayHeader(date: monday.add(Duration(days: i)))),
              ]),
            ),
            Container(
              decoration: BoxDecoration(
                  border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: .55)),
                  borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: slots.length * rowHeight,
                child: Stack(
                  children: [
                    for (var i = 0; i <= slots.length; i++)
                      Positioned(
                          left: periodWidth,
                          right: 0,
                          top: i * rowHeight,
                          child: Divider(
                              height: 1,
                              color:
                                  colors.outlineVariant.withValues(alpha: .4))),
                    for (var day = 0; day < 7; day++)
                      Positioned(
                          left: periodWidth +
                              day * ((contentWidth - periodWidth) / 7),
                          top: 0,
                          bottom: 0,
                          child: VerticalDivider(
                              width: 1,
                              color: colors.outlineVariant
                                  .withValues(alpha: .32))),
                    for (var i = 0; i < slots.length; i++)
                      Positioned(
                          left: 0,
                          top: i * rowHeight,
                          width: periodWidth,
                          height: rowHeight,
                          child: _SlotLabel(slot: slots[i])),
                    ..._lessonCards(context, contentWidth),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.swipe_outlined,
                  size: 15, color: colors.onSurfaceVariant),
              const SizedBox(width: 5),
              Text('课程卡片可点开编辑 · 冲突课程会合并显示',
                  style:
                      TextStyle(fontSize: 11, color: colors.onSurfaceVariant))
            ]),
          ],
        ),
      ),
    );
  }

  List<Widget> _lessonCards(BuildContext context, double contentWidth) {
    final cards = <Widget>[];
    for (var day = 0; day < 7; day++) {
      final date = monday.add(Duration(days: day));
      final dayLessons = displayOccurrencesForDate(
        controller.data,
        term,
        date,
      ).where((lesson) => lesson.isCurrentWeek).toList(growable: false);
      final groups = groupOccurrencesByTime(dayLessons);
      final lanes = <List<OccurrenceGroup>>[];
      for (final group in groups) {
        var lane = 0;
        while (lane < lanes.length &&
            lanes[lane].any((other) =>
                group.startSlot <= other.endSlot &&
                other.startSlot <= group.endSlot)) {
          lane++;
        }
        if (lane == lanes.length) lanes.add([]);
        lanes[lane].add(group);
      }
      for (var lane = 0; lane < lanes.length; lane++) {
        for (final group in lanes[lane]) {
          final dayWidthActual = (contentWidth - periodWidth) / 7;
          final span = (group.endSlot - group.startSlot + 1)
              .clamp(1, term.slots.length)
              .toDouble();
          final top = (term.slots
                      .indexWhere((slot) => slot.index == group.startSlot)
                      .clamp(0, term.slots.length - 1))
                  .toDouble() *
              rowHeight;
          final left = periodWidth +
              day * dayWidthActual +
              lane * (dayWidthActual / lanes.length);
          final cardWidth = dayWidthActual / lanes.length;
          cards.add(Positioned(
              left: left + 2,
              top: top + 2,
              width: cardWidth - 4,
              height: span * rowHeight - 4,
              child: _LessonCard(
                group: group,
                onTap: () => showOccurrenceGroupOrDetail(
                  context,
                  controller,
                  term,
                  group,
                ),
              )));
        }
      }
    }
    return cards;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final today = model.dateKey(date) == model.dateKey(DateTime.now());
    final color = today
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(weekdayName(date.weekday),
          style: TextStyle(
              fontWeight: FontWeight.w700, color: color, fontSize: 12)),
      const SizedBox(height: 2),
      Text('${date.month}/${date.day}',
          style: TextStyle(color: color, fontSize: 11))
    ]);
  }
}

class _SlotLabel extends StatelessWidget {
  const _SlotLabel({required this.slot});
  final model.TimeSlot slot;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(children: [
        Text('${slot.index}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(formatTime(slot.startMinutes),
            style: TextStyle(
                fontSize: 8,
                color: Theme.of(context).colorScheme.onSurfaceVariant))
      ]));
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.group, required this.onTap});
  final OccurrenceGroup group;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final primary = group.primary;
    final lesson = primary.occurrence;
    final color = _lessonColor(context, primary);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color.withValues(alpha: primary.isCurrentWeek ? .18 : .11),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border(left: BorderSide(color: color, width: 3))),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lesson.course.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: color)),
                    if (group.hasOverlap)
                      Text('第 ${lesson.startSlot}-${lesson.endSlot} 节',
                          style: TextStyle(
                              fontSize: 8, color: scheme.onSurfaceVariant)),
                    if (lesson.room.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(lesson.room,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 9, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (group.hasOverlap)
                Positioned(
                  top: 0,
                  right: 0,
                  child: _OverlapBadge(
                      count: group.occurrences.length, color: color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _lessonColor(BuildContext context, DisplayOccurrence lesson) {
  if (!lesson.isCurrentWeek) {
    // Off-week courses retain their place in the timetable but are fully
    // neutral so they cannot be mistaken for an active lesson.  The course
    // colour remains available when the user opens its details.
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
  return Color(lesson.occurrence.course.color);
}

/// A compact diagonal corner marker keeps conflict cards readable at narrow
/// phone widths.  The count remains available through the accessible label and
/// tooltip while the card itself shows the familiar stacked-layers symbol.
class _OverlapBadge extends StatelessWidget {
  const _OverlapBadge({this.count = 2, this.color});

  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;
    return Tooltip(
      message: '$count 门课程重叠，点击查看',
      child: Semantics(
        button: true,
        label: '$count 门课程重叠，点击查看',
        child: SizedBox(
          width: 25,
          height: 25,
          child: CustomPaint(
            painter: _OverlapCornerPainter(tint),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 2),
                child: Icon(Icons.layers_rounded, size: 11, color: tint),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlapCornerPainter extends CustomPainter {
  const _OverlapCornerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final triangle = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(triangle, Paint()..color = color.withValues(alpha: .18));
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width, size.height),
      Paint()
        ..color = color.withValues(alpha: .62)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_OverlapCornerPainter oldDelegate) =>
      oldDelegate.color != color;
}

class DaySchedule extends StatelessWidget {
  const DaySchedule(
      {super.key,
      required this.controller,
      required this.term,
      required this.date});
  final ScheduleController controller;
  final model.Term term;
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final lessons = displayOccurrencesForDate(controller.data, term, date)
        .where((lesson) => lesson.isCurrentWeek)
        .toList(growable: false);
    final groups = groupOccurrencesByTime(lessons);
    if (groups.isEmpty) {
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(22),
              child: Center(
                  child: Text('这一天没有课程',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)))));
    }
    return Column(children: [
      for (final group in groups)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DayLessonTile(
                group: group, term: term, controller: controller))
    ]);
  }
}

class _DayLessonTile extends StatelessWidget {
  const _DayLessonTile(
      {required this.group, required this.term, required this.controller});
  final OccurrenceGroup group;
  final model.Term term;
  final ScheduleController controller;
  @override
  Widget build(BuildContext context) {
    final primary = group.primary;
    final lesson = primary.occurrence;
    final color = _lessonColor(context, primary);
    // The card may cover the union of overlapping ranges.  Details still
    // report the primary lesson's own range so a 1-2 + 2-3 collision is not
    // misread as one 1-3 lesson.
    final start =
        term.slots.where((s) => s.index == lesson.startSlot).firstOrNull;
    final end = term.slots.where((s) => s.index == lesson.endSlot).firstOrNull;
    return Card(
        child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () =>
                showOccurrenceGroupOrDetail(context, controller, term, group),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                      width: 4,
                      height: 50,
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Expanded(
                              child: Text(lesson.course.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700))),
                          if (group.hasOverlap)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: _OverlapBadge(
                                count: group.occurrences.length,
                                color: color,
                              ),
                            ),
                        ]),
                        const SizedBox(height: 5),
                        Text(
                            '${start == null ? '' : formatTime(start.startMinutes)} – ${end == null ? '' : formatTime(end.endMinutes)}  ·  ${lesson.room.isEmpty ? '地点未填' : lesson.room}${primary.isCurrentWeek ? '' : '  ·  非本周'}',
                            style: Theme.of(context).textTheme.bodySmall)
                      ])),
                  const Icon(Icons.chevron_right_rounded)
                ]))));
  }
}

Future<void> showOccurrenceGroupOrDetail(
  BuildContext context,
  ScheduleController controller,
  model.Term term,
  OccurrenceGroup group,
) async {
  if (!group.hasOverlap) {
    await showCourseDetail(
      context,
      controller,
      term,
      group.primary.occurrence,
    );
    return;
  }
  await showOccurrenceGroup(context, controller, term, group);
}

Future<void> showOccurrenceGroup(
  BuildContext context,
  ScheduleController controller,
  model.Term term,
  OccurrenceGroup group,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('同一时段的课程',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${weekdayName(group.date.weekday)}  ·  第 ${group.startSlot}-${group.endSlot} 节  ·  共 ${group.occurrences.length} 门',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: group.occurrences.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final entry = group.occurrences[index];
                      final lesson = entry.occurrence;
                      final color = _lessonColor(sheetContext, entry);
                      return Material(
                        color: color.withValues(
                            alpha: entry.isCurrentWeek ? .13 : .08),
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          onTap: () {
                            Navigator.pop(sheetContext);
                            showCourseDetail(context, controller, term, lesson);
                          },
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          leading: Container(
                            width: 4,
                            height: 42,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          title: Text(lesson.course.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${lesson.room.isEmpty ? '地点未填' : lesson.room}${lesson.course.teacher.isEmpty ? '' : '  ·  ${lesson.course.teacher}'}${entry.isCurrentWeek ? '' : '  ·  非本周'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> showCourseDetail(
    BuildContext context,
    ScheduleController controller,
    model.Term term,
    model.LessonOccurrence event) async {
  final originalDate = controller.data.overrides
          .where((item) => item.id == event.overrideId)
          .firstOrNull
          ?.originalDate ??
      event.date;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 25),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(event.course.title,
                        style: Theme.of(sheetContext)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800))),
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: Color(event.course.color),
                        shape: BoxShape.circle))
              ]),
              const SizedBox(height: 16),
              _CourseDetailFields(term: term, event: event),
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showCourseEditor(context, controller, term,
                          initial: event.course);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑整学期')),
                OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _showOneOffMenu(
                          context, controller, term, event, originalDate);
                    },
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('仅本次')),
                TextButton.icon(
                    onPressed: () async {
                      final ok =
                          await _confirm(context, '删除整门课程？', '这会移除本学期的所有上课安排。');
                      if (ok) {
                        await controller.deleteCourse(event.course.id);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除')),
              ]),
            ]),
      ),
    ),
  );
}

class _CourseDetailFields extends StatelessWidget {
  const _CourseDetailFields({required this.term, required this.event});

  final model.Term term;
  final model.LessonOccurrence event;

  @override
  Widget build(BuildContext context) {
    final course = event.course;
    final start =
        term.slots.where((slot) => slot.index == event.startSlot).firstOrNull;
    final end =
        term.slots.where((slot) => slot.index == event.endSlot).firstOrNull;
    final time = start == null || end == null
        ? '${weekdayName(event.date.weekday)} · 第 ${event.startSlot}-${event.endSlot} 节'
        : '${weekdayName(event.date.weekday)}  ${formatTime(start.startMinutes)}–${formatTime(end.endMinutes)}';
    final credits = course.credits == null
        ? '未设置'
        : course.credits!.toStringAsFixed(
            course.credits! % 1 == 0 ? 0 : 1,
          );
    final scheme = Theme.of(context).colorScheme;
    final fields = [
      ('上课时间', time),
      ('上课地点', course.room.trim().isEmpty ? '未设置' : course.room),
      ('任课教师', course.teacher.trim().isEmpty ? '未设置' : course.teacher),
      ('学分', credits),
    ];
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .44),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var index = 0; index < fields.length; index++) ...[
            _CourseDetailRow(label: fields[index].$1, value: fields[index].$2),
            if (index < fields.length - 1)
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: .42),
              ),
          ],
        ],
      ),
    );
  }
}

class _CourseDetailRow extends StatelessWidget {
  const _CourseDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 68,
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

Future<void> _showOneOffMenu(
    BuildContext context,
    ScheduleController controller,
    model.Term term,
    model.LessonOccurrence event,
    DateTime originalDate) async {
  final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('停课这一次'),
                onTap: () => Navigator.pop(context, 'cancel')),
            ListTile(
                leading: const Icon(Icons.event_repeat_outlined),
                title: const Text('调到其他日期'),
                onTap: () => Navigator.pop(context, 'move')),
            if (event.overrideId != null)
              ListTile(
                  leading: const Icon(Icons.undo_outlined),
                  title: const Text('撤销这次改动'),
                  onTap: () => Navigator.pop(context, 'undo')),
            const SizedBox(height: 10)
          ])));
  if (action == 'cancel') {
    await controller.saveOverride(model.LessonOverride(
        id: event.overrideId ??
            'override-${DateTime.now().microsecondsSinceEpoch}',
        courseId: event.course.id,
        originalDate: originalDate,
        cancelled: true));
  } else if (action == 'move' && context.mounted) {
    final date = await showDatePicker(
        context: context,
        initialDate: event.date,
        firstDate: term.startMonday,
        lastDate: term.startMonday.add(Duration(days: term.weekCount * 7 - 1)),
        helpText: '选择调课日期',
        cancelText: '取消',
        confirmText: '确定');
    if (date != null) {
      await controller.saveOverride(model.LessonOverride(
          id: event.overrideId ??
              'override-${DateTime.now().microsecondsSinceEpoch}',
          courseId: event.course.id,
          originalDate: originalDate,
          cancelled: false,
          date: model.dateOnly(date),
          startSlot: event.startSlot,
          endSlot: event.endSlot,
          room: event.room));
    }
  } else if (action == 'undo' && event.overrideId != null) {
    await controller.removeOverride(event.overrideId!);
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    (await showDialog<bool>(
        context: context,
        builder: (context) =>
            AlertDialog(title: Text(title), content: Text(body), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确定'))
            ]))) ??
    false;

Future<void> showCourseEditor(
    BuildContext context, ScheduleController controller, model.Term term,
    {model.Course? initial}) async {
  final course = await showModalBottomSheet<model.Course>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => CourseEditor(term: term, initial: initial));
  if (course != null) await controller.saveCourse(course);
}

class CourseEditor extends StatefulWidget {
  const CourseEditor({super.key, required this.term, this.initial});
  final model.Term term;
  final model.Course? initial;
  @override
  State<CourseEditor> createState() => _CourseEditorState();
}

class _CourseEditorState extends State<CourseEditor> {
  late final TextEditingController title;
  late final TextEditingController teacher;
  late final TextEditingController room;
  late final TextEditingController credits;
  late final TextEditingController weeks;
  late int weekday;
  late int start;
  late int end;
  late int color;
  String? error;
  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    title = TextEditingController(text: c?.title ?? '');
    teacher = TextEditingController(text: c?.teacher ?? '');
    room = TextEditingController(text: c?.room ?? '');
    credits =
        TextEditingController(text: c?.credits == null ? '' : '${c!.credits}');
    weeks = TextEditingController(
        text: c?.weeks.join(',') ?? '1-${widget.term.weekCount}');
    weekday = c?.weekday ?? 1;
    start = c?.startSlot ?? widget.term.slots.first.index;
    end = c?.endSlot ?? start;
    color = c?.color ?? 0xFF147D78;
  }

  @override
  void dispose() {
    title.dispose();
    teacher.dispose();
    room.dispose();
    credits.dispose();
    weeks.dispose();
    super.dispose();
  }

  void save() {
    final parsedWeeks = parseWeeks(weeks.text, widget.term.weekCount);
    if (title.text.trim().isEmpty) return setState(() => error = '请填写课程名称');
    if (parsedWeeks == null || parsedWeeks.isEmpty) {
      return setState(() => error = '周次格式无法识别，例如 1-16、单周或 1,3,5');
    }
    if (end < start) return setState(() => error = '结束节次不能早于开始节次');
    final creditsText = credits.text.trim();
    final parsedCredits =
        creditsText.isEmpty ? null : double.tryParse(creditsText);
    if (creditsText.isNotEmpty &&
        (parsedCredits == null || parsedCredits < 0)) {
      return setState(() => error = '学分请输入非负数字');
    }
    Navigator.pop(
        context,
        model.Course(
            id: widget.initial?.id ??
                'course-${DateTime.now().microsecondsSinceEpoch}',
            termId: widget.term.id,
            title: title.text.trim(),
            teacher: teacher.text.trim(),
            room: room.text.trim(),
            weekday: weekday,
            startSlot: start,
            endSlot: end,
            weeks: parsedWeeks,
            color: color,
            credits: parsedCredits));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.initial == null ? '添加课程' : '编辑课程',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: '课程名称', prefixIcon: Icon(Icons.book_outlined))),
          const SizedBox(height: 12),
          TextField(
              controller: credits,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: '学分（可选）',
                  prefixIcon: Icon(Icons.school_outlined))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: teacher,
                    decoration: const InputDecoration(labelText: '教师'))),
            const SizedBox(width: 10),
            Expanded(
                child: TextField(
                    controller: room,
                    decoration: const InputDecoration(labelText: '教室')))
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
              initialValue: weekday,
              decoration: const InputDecoration(labelText: '星期'),
              items: [
                for (var d = 1; d <= 7; d++)
                  DropdownMenuItem(value: d, child: Text(weekdayName(d)))
              ],
              onChanged: (v) => setState(() => weekday = v ?? 1)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: DropdownButtonFormField<int>(
                    initialValue: start,
                    decoration: const InputDecoration(labelText: '开始节次'),
                    items: [
                      for (final s in widget.term.slots)
                        DropdownMenuItem(
                            value: s.index, child: Text('第 ${s.index} 节'))
                    ],
                    onChanged: (v) => setState(() {
                          start = v ?? start;
                          if (end < start) end = start;
                        }))),
            const SizedBox(width: 10),
            Expanded(
                child: DropdownButtonFormField<int>(
                    initialValue: end,
                    decoration: const InputDecoration(labelText: '结束节次'),
                    items: [
                      for (final s in widget.term.slots)
                        DropdownMenuItem(
                            value: s.index, child: Text('第 ${s.index} 节'))
                    ],
                    onChanged: (v) => setState(() => end = v ?? end)))
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: weeks,
              decoration: const InputDecoration(
                  labelText: '周次',
                  hintText: '例如 1-16、单周、1,3,5',
                  prefixIcon: Icon(Icons.repeat))),
          const SizedBox(height: 13),
          Text('颜色', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
              spacing: 10,
              children: [
                0xFF147D78,
                0xFF4679D7,
                0xFFB56A34,
                0xFF8A5AB8,
                0xFFC45064,
                0xFF358A62
              ]
                  .map((item) => InkWell(
                      onTap: () => setState(() => color = item),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              color: Color(item),
                              shape: BoxShape.circle,
                              border: color == item
                                  ? Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      width: 3)
                                  : null))))
                  .toList()),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 20),
          SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: save, child: const Text('保存课程'))),
        ])),
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
