import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kejian/app_controller.dart';
import 'package:kejian/data/storage_repository.dart';
import 'package:kejian/domain/models.dart' as model;
import 'package:kejian/domain/schedule_helpers.dart';
import 'package:kejian/services/reminder_service.dart';
import 'package:kejian/ui/app_theme.dart';
import 'package:kejian/ui/schedule_page.dart';

class _MemoryRepository extends StorageRepository {
  model.ScheduleData value = model.ScheduleData.blank();

  @override
  Future<model.ScheduleData> load() async => value;

  @override
  Future<void> save(model.ScheduleData data) async {
    data.validate();
    value = data;
  }
}

class _TestReminders extends ReminderService {
  @override
  Future<ReminderStatus> status() async => const ReminderStatus(
        supported: false,
        permission: ReminderPermission.unknown,
      );

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<int> schedule(List<ReminderPlan> reminders) async => reminders.length;

  @override
  Future<bool> cancel() async => true;
}

model.Term _term() => model.Term(
      id: 'term',
      name: '本周学期',
      startMonday: mondayOf(DateTime.now()),
      weekCount: 4,
      slots: model.Term.defaultSlots(),
    );

model.Course _course(
  model.Term term, {
  required String id,
  required String title,
  required List<int> weeks,
  int color = 0xFF336699,
}) =>
    model.Course(
      id: id,
      termId: term.id,
      title: title,
      teacher: '教师',
      room: '$id 教室',
      weekday: DateTime.monday,
      startSlot: 1,
      endSlot: 2,
      weeks: weeks,
      color: color,
    );

model.ScheduleData _schedule(
  model.Term term,
  List<model.Course> courses,
) =>
    model.ScheduleData(
      terms: [term],
      activeTermId: term.id,
      courses: courses,
      overrides: const [],
      settings: model.AppSettings(),
    );

Future<ScheduleController> _controller(model.ScheduleData data) async {
  final controller = ScheduleController(
    repository: _MemoryRepository(),
    reminderService: _TestReminders(),
  );
  await controller.restoreData(data);
  return controller;
}

Widget _app(ScheduleController controller) => MaterialApp(
      theme: buildKejianTheme(Brightness.light),
      home: Scaffold(body: SchedulePage(controller: controller)),
    );

void main() {
  testWidgets('overlap badge opens every lesson in the group', (tester) async {
    final term = _term();
    final controller = await _controller(
      _schedule(term, [
        _course(term, id: 'active', title: '本周课程', weeks: const [1]),
        _course(term, id: 'retake', title: '重修课程', weeks: const [2]),
      ]),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('还有1门'), findsOneWidget);
    await tester.tap(find.text('还有1门'));
    await tester.pumpAndSettle();

    expect(find.text('同一时段的课程'), findsOneWidget);
    // The compact card remains in the route's subtree under the modal.
    expect(find.text('本周课程'), findsAtLeastNWidgets(2));
    expect(find.text('重修课程'), findsOneWidget);
    expect(find.textContaining('非本周'), findsOneWidget);
  });

  testWidgets('inactive course uses neutral surface color', (tester) async {
    final term = _term();
    final controller = await _controller(
      _schedule(term, [
        _course(term, id: 'alternate', title: '隔周课程', weeks: const [2]),
      ]),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('隔周课程'));
    final context = tester.element(find.text('隔周课程'));
    expect(title.style?.color, Theme.of(context).colorScheme.onSurfaceVariant);
  });

  testWidgets('evening lessons render in the late timetable rows',
      (tester) async {
    final term = _term();
    final controller = await _controller(
      _schedule(term, [
        model.Course(
          id: 'evening',
          termId: term.id,
          title: '晚间课程',
          teacher: '教师',
          room: '夜间教室',
          weekday: DateTime.tuesday,
          startSlot: 9,
          endSlot: 11,
          weeks: const [1],
          color: 0xFF336699,
        ),
      ]),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.text('晚间课程'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
  });
}
