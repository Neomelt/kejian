import 'dart:convert';
import 'dart:typed_data';

import '../domain/models.dart';

/// Export a portable CSV understood by the CSV importer in this package.
String exportCoursesCsv(Term term, Iterable<Course> courses) {
  final out = StringBuffer('\uFEFF课程名称,教师,教室,星期,节次,周次,颜色\r\n');
  for (final course in courses.where((c) => c.termId == term.id)) {
    final row = <String>[
      course.title,
      course.teacher,
      course.room,
      '周${course.weekday}',
      course.startSlot == course.endSlot
          ? '${course.startSlot}节'
          : '${course.startSlot}-${course.endSlot}节',
      _formatWeeks(course.weeks),
      '#${course.color.toRadixString(16).padLeft(8, '0')}',
    ];
    out.write(row.map(_csvCell).join(','));
    out.write('\r\n');
  }
  return out.toString();
}

Uint8List exportCoursesCsvBytes(Term term, Iterable<Course> courses) =>
    Uint8List.fromList(utf8.encode(exportCoursesCsv(term, courses)));

/// Export each concrete occurrence instead of an RRULE. This preserves exact
/// teaching weeks and is safe for calendars that implement only a subset of
/// RFC 5545 recurrence rules.
String exportCoursesIcs(
  Term term,
  Iterable<Course> courses, {
  Iterable<LessonOverride> overrides = const [],
}) {
  final out = StringBuffer(
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//KeJian//Schedule//EN\r\nCALSCALE:GREGORIAN\r\n',
  );
  for (final course in courses.where((c) => c.termId == term.id)) {
    final weeks = course.weeks.toSet().toList()..sort();
    for (final week in weeks) {
      if (week < 1 || week > term.weekCount) continue;
      final originalDate = DateTime(
        term.startMonday.year,
        term.startMonday.month,
        term.startMonday.day,
      ).add(Duration(days: (week - 1) * 7 + course.weekday - 1));
      LessonOverride? override;
      for (final candidate in overrides) {
        if (candidate.courseId == course.id &&
            _sameDate(candidate.originalDate, originalDate)) {
          override = candidate;
          break;
        }
      }
      if (override?.cancelled == true) continue;
      final date = override?.date ?? originalDate;
      final startSlot = override?.startSlot ?? course.startSlot;
      final endSlot = override?.endSlot ?? course.endSlot;
      final start = _slot(term, startSlot);
      final end = _slot(term, endSlot);
      if (start == null || end == null) continue;
      final startAt = DateTime(
        date.year,
        date.month,
        date.day,
        start.startMinutes ~/ 60,
        start.startMinutes % 60,
      );
      final endAt = DateTime(
        date.year,
        date.month,
        date.day,
        end.endMinutes ~/ 60,
        end.endMinutes % 60,
      );
      out
        ..write('BEGIN:VEVENT\r\n')
        ..write('UID:${course.id}-$week@kejian\r\n')
        ..write('DTSTAMP:${_icsDateTime(DateTime.now().toUtc())}Z\r\n')
        ..write('DTSTART:${_icsDateTime(startAt)}\r\n')
        ..write('DTEND:${_icsDateTime(endAt)}\r\n')
        ..write('SUMMARY:${_icsEscape(course.title)}\r\n')
        ..write('LOCATION:${_icsEscape(override?.room ?? course.room)}\r\n')
        ..write('DESCRIPTION:${_icsEscape(course.teacher)}\r\n')
        ..write('END:VEVENT\r\n');
    }
  }
  out.write('END:VCALENDAR\r\n');
  return out.toString();
}

Uint8List exportCoursesIcsBytes(
  Term term,
  Iterable<Course> courses, {
  Iterable<LessonOverride> overrides = const [],
}) =>
    Uint8List.fromList(
      utf8.encode(exportCoursesIcs(term, courses, overrides: overrides)),
    );

String _formatWeeks(List<int> weeks) {
  final sorted = weeks.toSet().toList()..sort();
  if (sorted.isEmpty) return '';
  final ranges = <String>[];
  var start = sorted.first;
  var previous = start;
  for (final week in sorted.skip(1)) {
    if (week != previous + 1) {
      ranges.add(start == previous ? '$start' : '$start-$previous');
      start = week;
    }
    previous = week;
  }
  ranges.add(start == previous ? '$start' : '$start-$previous');
  return '${ranges.join(',')}周';
}

String _csvCell(String value) {
  if (value.contains(RegExp(r'[,"\r\n]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

TimeSlot? _slot(Term term, int index) {
  for (final slot in term.slots) {
    if (slot.index == index) return slot;
  }
  return null;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _icsDateTime(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}T${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}00';
String _icsEscape(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\n', '\\n');
