import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kejian/app_controller.dart';
import 'package:kejian/data/storage_repository.dart';
import 'package:kejian/domain/models.dart' as model;
import 'package:kejian/main.dart';
import 'package:kejian/services/reminder_service.dart';

class _TestReminders extends ReminderService {
  _TestReminders();

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

class _MemoryRepository extends StorageRepository {
  model.ScheduleData value = model.ScheduleData.blank();
  final Map<int, model.ScheduleData> revisions = {};
  int nextRevision = 1;

  @override
  Future<model.ScheduleData> load() async => value;

  @override
  Future<void> save(model.ScheduleData data) async {
    data.validate();
    value = data;
  }

  @override
  Future<SnapshotInfo> snapshot([model.ScheduleData? data]) async {
    final id = nextRevision++;
    revisions[id] = data ?? value;
    return SnapshotInfo(id: id, createdAt: DateTime.utc(2026, 1, id));
  }

  @override
  Future<List<SnapshotInfo>> listSnapshots() async => [
        for (final entry in revisions.entries)
          SnapshotInfo(
              id: entry.key, createdAt: DateTime.utc(2026, 1, entry.key)),
      ];

  @override
  Future<model.ScheduleData> restore(int id) async {
    final restored = revisions[id];
    if (restored == null) throw StorageException('missing');
    await save(restored);
    return restored;
  }
}

ScheduleController memoryController() => ScheduleController(
      repository: _MemoryRepository(),
      reminderService: _TestReminders(),
    );

void main() {
  testWidgets('blank state guides the first setup', (tester) async {
    final controller = memoryController();
    await controller.init();
    await tester.pumpWidget(KejianApp(controller: controller));
    expect(find.text('先把学期放进来'), findsOneWidget);
    expect(find.text('创建学期'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
  });

  testWidgets('sample timetable renders a narrow dark screen', (tester) async {
    final controller = memoryController();
    await controller.init();
    await controller.restoreData(model.ScheduleData.sample());
    await controller.updateSettings(themeMode: model.ThemeMode.dark);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(KejianApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('课间'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month), findsWidgets);
  });
}
