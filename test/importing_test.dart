import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kejian/domain/models.dart';
import 'package:kejian/importing/importing.dart';

Term testTerm() => Term(
      id: 'spring',
      name: '测试学期',
      startMonday: DateTime(2026, 2, 23),
      weekCount: 16,
      slots: Term.defaultSlots(),
    );

void main() {
  test('CSV handles Chinese headers, quoted commas, ranges and odd weeks', () {
    final csv = '课程名称,教师,教室,星期,节次,周次\n'
        '"程序设计,实验",张老师,A101,周一,1-2节,1-16周\n'
        '英语,,B202,3,第3节,"单周"\n'
        '重复,,B202,3,3节,1,\n'
        '坏行,,B202,周九,3节,1周\n';
    final result = parseCsv(Uint8List.fromList(utf8.encode(csv)), testTerm());
    expect(result.courses, hasLength(3));
    expect(result.courses.first.title, '程序设计,实验');
    expect(result.courses.first.weeks, List<int>.generate(16, (i) => i + 1));
    expect(result.courses[1].weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    expect(parseWeeks('1-16周（双）', 16), [2, 4, 6, 8, 10, 12, 14, 16]);
    expect(result.skippedRows, 1);
    expect(result.hasErrors, isTrue);
  });

  test('CSV retains same-title lessons at different placements', () {
    final csv = '课程名称,教师,教室,星期,节次,周次\n'
        '重修英语,李老师,A101,周一,1-2节,1-16周\n'
        '重修英语,李老师,A101,周四,9-11节,1-16周\n';
    final result = parseCsv(Uint8List.fromList(utf8.encode(csv)), testTerm());

    expect(result.courses, hasLength(2));
    expect(
      result.courses
          .map(
            (course) =>
                '${course.weekday}:${course.startSlot}-${course.endSlot}',
          )
          .toSet(),
      {'1:1-2', '4:9-11'},
    );
  });

  test(
    'ICS expands supported weekly recurrence and rejects cross-day event',
    () {
      final ics = '''BEGIN:VCALENDAR\r
VERSION:2.0\r
BEGIN:VEVENT\r
DTSTART:20260223T080000\r
DTEND:20260223T094000\r
RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3\r
SUMMARY:线性代数\r
LOCATION:C301\r
DESCRIPTION:教师:李老师\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART:20260224T230000\r
DTEND:20260225T010000\r
SUMMARY:跨日\r
END:VEVENT\r
END:VCALENDAR\r
''';
      final result = parseIcs(Uint8List.fromList(utf8.encode(ics)), testTerm());
      expect(result.courses, hasLength(1));
      expect(result.courses.single.weeks, [1, 2, 3]);
      expect(result.courses.single.teacher, '李老师');
      expect(result.diagnostics.any((d) => d.message.contains('跨日')), isTrue);
    },
  );

  test('backup round-trip preserves validated schedule', () {
    final term = testTerm();
    final schedule = ScheduleData(
      terms: [term],
      activeTermId: term.id,
      courses: [
        Course(
          id: 'c1',
          termId: term.id,
          title: '课程',
          teacher: '',
          room: 'A',
          weekday: 1,
          startSlot: 1,
          endSlot: 2,
          weeks: [1, 3],
          color: 0xFF5E6AD2,
        ),
      ],
      overrides: const [],
      settings: AppSettings(),
    );
    final restored = decodeScheduleBackup(encodeScheduleBackup(schedule));
    expect(restored, schedule);
    expect(
      () => decodeScheduleBackup('{"format":"wrong"}'),
      throwsFormatException,
    );
  });

  test('ICS export emits concrete dates and CSV re-imports them', () {
    final term = testTerm();
    final course = Course(
      id: 'c1',
      termId: term.id,
      title: '课程',
      teacher: '老师',
      room: 'A101',
      weekday: 1,
      startSlot: 1,
      endSlot: 2,
      weeks: [1, 3],
      color: 0xFF5E6AD2,
    );
    final ics = exportCoursesIcs(term, [course]);
    expect(RegExp('BEGIN:VEVENT').allMatches(ics), hasLength(2));
    final csv = exportCoursesCsv(term, [course]);
    final imported = parseCsv(Uint8List.fromList(utf8.encode(csv)), term);
    expect(imported.courses.single.weeks, [1, 3]);
  });
}
