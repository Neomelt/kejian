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

  Course course({
    required String id,
    required String title,
    required int startSlot,
    required int endSlot,
    required List<int> weeks,
    int weekday = DateTime.monday,
  }) =>
      Course(
        id: id,
        termId: term.id,
        title: title,
        teacher: '',
        room: '$id-room',
        weekday: weekday,
        startSlot: startSlot,
        endSlot: endSlot,
        weeks: weeks,
        color: 0xFF336699,
      );

  ScheduleData schedule(List<Course> courses) => ScheduleData(
        terms: [term],
        activeTermId: term.id,
        courses: courses,
        overrides: const [],
        settings: AppSettings(),
      );

  test('alternate-week lessons remain visible and are marked inactive', () {
    final current = course(
      id: 'current',
      title: '本周课程',
      startSlot: 1,
      endSlot: 2,
      weeks: const [1],
    );
    final alternate = course(
      id: 'alternate',
      title: '隔周课程',
      startSlot: 1,
      endSlot: 2,
      weeks: const [2],
    );

    final displayed = displayOccurrencesForDate(
      schedule([current, alternate]),
      term,
      term.startMonday,
    );

    expect(displayed, hasLength(2));
    final byId = {
      for (final item in displayed) item.occurrence.course.id: item,
    };
    expect(byId['current']!.isCurrentWeek, isTrue);
    expect(byId['alternate']!.isCurrentWeek, isFalse);
  });

  test('display projection excludes another weekday', () {
    final monday = course(
      id: 'mon',
      title: '周一',
      startSlot: 1,
      endSlot: 1,
      weeks: const [1],
    );
    final tuesday = course(
      id: 'tue',
      title: '周二',
      startSlot: 1,
      endSlot: 1,
      weeks: const [1],
      weekday: DateTime.tuesday,
    );

    final displayed = displayOccurrencesForDate(
      schedule([monday, tuesday]),
      term,
      term.startMonday,
    );

    expect(displayed.map((item) => item.occurrence.course.id), ['mon']);
  });

  test('overlapping groups are transitive and keep non-overlaps separate', () {
    final date = term.startMonday;
    final first = course(
      id: 'first',
      title: '第一门',
      startSlot: 1,
      endSlot: 2,
      weeks: const [1],
    );
    final second = course(
      id: 'second',
      title: '第二门',
      startSlot: 2,
      endSlot: 3,
      weeks: const [1],
    );
    final third = course(
      id: 'third',
      title: '第三门',
      startSlot: 3,
      endSlot: 4,
      weeks: const [1],
    );
    final separate = course(
      id: 'separate',
      title: '不冲突',
      startSlot: 6,
      endSlot: 7,
      weeks: const [1],
    );
    final nextDay = course(
      id: 'next-day',
      title: '下一天',
      startSlot: 1,
      endSlot: 2,
      weeks: const [1],
      weekday: DateTime.tuesday,
    );

    final data = schedule([first, second, third, separate, nextDay]);
    final weekOne = displayOccurrencesForDate(data, term, date);
    final weekTwo = displayOccurrencesForDate(
      data,
      term,
      date.add(const Duration(days: 1)),
    );
    final groups = groupOccurrencesByTime([
      ...weekOne,
      ...weekTwo,
    ]);

    expect(groups, hasLength(3));
    final idsByGroup = groups
        .map((group) =>
            (group.occurrences.map((item) => item.occurrence.course.id).toList()
                  ..sort())
                .join(','))
        .toSet();
    expect(
      idsByGroup,
      containsAll(<String>['first,second,third', 'separate', 'next-day']),
    );
  });

  test('group primary prefers current-week occurrence', () {
    final inactive = course(
      id: 'inactive',
      title: 'A-隔周课程',
      startSlot: 1,
      endSlot: 2,
      weeks: const [2],
    );
    final current = course(
      id: 'current',
      title: 'Z-本周课程',
      startSlot: 1,
      endSlot: 2,
      weeks: const [1],
    );
    final displayed = displayOccurrencesForDate(
      schedule([inactive, current]),
      term,
      term.startMonday,
    );

    final group = groupOccurrencesByTime(displayed).single;
    expect(group.primary.isCurrentWeek, isTrue);
    expect(group.primary.occurrence.course.id, 'current');
  });
}
