import 'package:flutter_test/flutter_test.dart';
import 'package:kejian/domain/domain.dart';

void main() {
  final term = Term(
    id: 't1',
    name: '春季学期',
    startMonday: DateTime(2026, 2, 23),
    weekCount: 4,
    slots: Term.defaultSlots(),
  );

  test('currentWeek preserves dates outside term', () {
    expect(currentWeek(term, DateTime(2026, 2, 23)), 1);
    expect(currentWeek(term, DateTime(2026, 2, 22)), 0);
    expect(currentWeek(term, DateTime(2026, 2, 9)), -1);
    expect(currentWeek(term, DateTime(2026, 3, 22)), 4);
  });

  test('JSON round trip preserves sample schedule', () {
    final value = ScheduleData.sample();
    expect(ScheduleJson.decode(ScheduleJson.encode(value)), value);
  });

  test('invalid backup schema and dangling references are rejected', () {
    expect(
      () => ScheduleJson.decode({'schemaVersion': 99}),
      throwsFormatException,
    );
    final value = ScheduleData.sample().toJson();
    final courses = (value['courses'] as List).cast<Map<String, dynamic>>();
    courses.first['termId'] = 'missing';
    expect(() => ScheduleJson.decode(value), throwsFormatException);
  });

  test('moved and cancelled lessons are reflected in occurrences', () {
    final course = Course(
      id: 'c1',
      termId: term.id,
      title: '课程',
      teacher: '',
      room: 'A101',
      weekday: DateTime.monday,
      startSlot: 1,
      endSlot: 2,
      weeks: const [1],
      color: 1,
    );
    final original = DateTime(2026, 2, 23);
    final moved = DateTime(2026, 2, 25);
    final schedule = ScheduleData(
      terms: [term],
      activeTermId: term.id,
      courses: [course],
      overrides: [
        LessonOverride(
          id: 'o1',
          courseId: course.id,
          originalDate: original,
          cancelled: false,
          date: moved,
          startSlot: 3,
          endSlot: 4,
          room: 'B201',
        ),
      ],
      settings: AppSettings(),
    );
    expect(occurrencesForDate(schedule, original), isEmpty);
    final result = occurrencesForDate(schedule, moved);
    expect(result, hasLength(1));
    expect(result.single.startSlot, 3);
    expect(result.single.room, 'B201');
  });

  test('overlapping lessons produce pair conflicts', () {
    final course = Course(
      id: 'c1',
      termId: term.id,
      title: '课程',
      teacher: '',
      room: 'A101',
      weekday: 1,
      startSlot: 1,
      endSlot: 2,
      weeks: const [1],
      color: 1,
    );
    final other = Course(
      id: 'c2',
      termId: term.id,
      title: '课程2',
      teacher: '',
      room: 'A102',
      weekday: 1,
      startSlot: 2,
      endSlot: 3,
      weeks: const [1],
      color: 2,
    );
    final data = ScheduleData(
      terms: [term],
      activeTermId: term.id,
      courses: [course, other],
      overrides: const [],
      settings: AppSettings(),
    );
    expect(conflicts(occurrencesForDate(data, term.startMonday)), hasLength(1));
  });
}
