import 'package:flutter_test/flutter_test.dart';
import 'package:kejian/domain/domain.dart';

void main() {
  final term = Term(
    id: 'term',
    name: '测试学期',
    startMonday: DateTime(2026, 2, 23),
    weekCount: 4,
    slots: Term.defaultSlots(),
  );

  Course course() => Course(
        id: 'course',
        termId: term.id,
        title: '课程',
        teacher: '教师',
        room: '原教室',
        weekday: DateTime.monday,
        startSlot: 1,
        endSlot: 2,
        weeks: const [1, 2],
        color: 0xFF336699,
      );

  ScheduleData schedule({required LessonOverride override}) => ScheduleData(
        terms: [term],
        activeTermId: term.id,
        courses: [course()],
        overrides: [override],
        settings: AppSettings(),
      );

  test('cancelled original lesson does not leave an inactive placeholder', () {
    final original = term.startMonday;
    final displayed = displayOccurrencesForDate(
      schedule(
        override: LessonOverride(
          id: 'cancelled',
          courseId: 'course',
          originalDate: original,
          cancelled: true,
        ),
      ),
      term,
      original,
    );

    expect(displayed, isEmpty);
  });

  test('moved lesson appears once at target with override details', () {
    final original = term.startMonday;
    final target = original.add(const Duration(days: 2));
    final data = schedule(
      override: LessonOverride(
        id: 'moved',
        courseId: 'course',
        originalDate: original,
        cancelled: false,
        date: target,
        startSlot: 4,
        endSlot: 5,
        room: '新教室',
      ),
    );

    final source = displayOccurrencesForDate(data, term, original);
    final destination = displayOccurrencesForDate(data, term, target);

    expect(source, isEmpty);
    expect(destination, hasLength(1));
    final moved = destination.single;
    expect(moved.isCurrentWeek, isTrue);
    expect(moved.occurrence.startSlot, 4);
    expect(moved.occurrence.endSlot, 5);
    expect(moved.occurrence.room, '新教室');
  });
}
