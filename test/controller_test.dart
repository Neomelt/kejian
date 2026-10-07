import 'package:flutter_test/flutter_test.dart';

import 'package:kejian/app_controller.dart';
import 'package:kejian/data/storage_repository.dart';
import 'package:kejian/domain/models.dart';
import 'package:kejian/domain/schedule_helpers.dart';
import 'package:kejian/services/reminder_service.dart';

class _MemoryRepository extends StorageRepository {
  ScheduleData value = ScheduleData.blank();
  final revisions = <int, ScheduleData>{};
  var nextRevision = 1;

  @override
  Future<ScheduleData> load() async => value;

  @override
  Future<void> save(ScheduleData data) async {
    data.validate();
    value = data;
  }

  @override
  Future<SnapshotInfo> snapshot([ScheduleData? data]) async {
    final id = nextRevision++;
    revisions[id] = data ?? value;
    return SnapshotInfo(id: id, createdAt: DateTime.utc(2026, 1, id));
  }

  @override
  Future<List<SnapshotInfo>> listSnapshots() async => revisions.keys
      .map((id) => SnapshotInfo(id: id, createdAt: DateTime.utc(2026, 1, id)))
      .toList();

  @override
  Future<ScheduleData> restore(int snapshotId) async {
    final restored = revisions[snapshotId];
    if (restored == null) throw StorageException('missing');
    await save(restored);
    return restored;
  }
}

class _NoopReminders extends ReminderService {
  _NoopReminders();

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

void main() {
  final term = Term(
    id: 'term',
    name: '测试学期',
    startMonday: DateTime(2026, 2, 23),
    weekCount: 16,
    slots: Term.defaultSlots(),
  );

  test('fresh init stays blank and CRUD waits for persisted state', () async {
    final repository = _MemoryRepository();
    final controller = ScheduleController(
      repository: repository,
      reminderService: _NoopReminders(),
      clock: () => DateTime(2026, 2, 23, 8),
    );
    await controller.init();
    expect(controller.data.terms, isEmpty);
    await Future.wait([
      controller.saveTerm(term),
      controller.saveTerm(
        Term(
          id: 'term2',
          name: '第二学期',
          startMonday: DateTime(2026, 9, 7),
          weekCount: 16,
          slots: Term.defaultSlots(),
        ),
      ),
    ]);
    expect(controller.data.terms.map((item) => item.id), ['term', 'term2']);
  });

  test('deleting a course removes its orphan lesson overrides', () async {
    final repository = _MemoryRepository();
    final controller = ScheduleController(
      repository: repository,
      reminderService: _NoopReminders(),
    );
    await controller.init();
    await controller.saveTerm(term);
    final course = Course(
      id: 'course',
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
    await controller.saveCourse(course);
    await controller.saveOverride(
      LessonOverride(
        id: 'override',
        courseId: course.id,
        originalDate: term.startMonday,
        cancelled: true,
      ),
    );
    await controller.deleteCourse(course.id);
    expect(controller.data.courses, isEmpty);
    expect(controller.data.overrides, isEmpty);
  });

  test('import keeps same-title lessons with different placements', () async {
    final repository = _MemoryRepository();
    final controller = ScheduleController(
      repository: repository,
      reminderService: _NoopReminders(),
    );
    await controller.init();
    await controller.saveTerm(term);

    final imported = [
      Course(
        id: 'capture-math-monday',
        termId: term.id,
        title: '同名课程',
        teacher: '同一教师',
        room: 'A101',
        weekday: DateTime.monday,
        startSlot: 1,
        endSlot: 2,
        weeks: const [1, 2, 3],
        color: 1,
      ),
      Course(
        id: 'capture-math-thursday',
        termId: term.id,
        title: '同名课程',
        teacher: '同一教师',
        room: 'A101',
        weekday: DateTime.thursday,
        startSlot: 9,
        endSlot: 11,
        weeks: const [1, 2, 3],
        color: 1,
      ),
    ];

    await controller.commitImportedCourses(imported);

    expect(controller.data.courses, hasLength(2));
    expect(
      controller.data.courses
          .map(
            (course) =>
                '${course.weekday}:${course.startSlot}-${course.endSlot}',
          )
          .toSet(),
      {'1:1-2', '4:9-11'},
    );
  });

  test('import commits evening slots that exist in the term', () async {
    final repository = _MemoryRepository();
    final controller = ScheduleController(
      repository: repository,
      reminderService: _NoopReminders(),
    );
    await controller.init();
    await controller.saveTerm(term);
    final evening = Course(
      id: 'capture-evening',
      termId: term.id,
      title: '晚间课程',
      teacher: '教师',
      room: '夜间教室',
      weekday: DateTime.tuesday,
      startSlot: 9,
      endSlot: 11,
      weeks: const [1],
      color: 2,
    );

    await controller.commitImportedCourses([evening]);

    expect(controller.data.courses, contains(evening));
    final occurrence = occurrencesForDate(
      controller.data,
      term.startMonday.add(const Duration(days: 1)),
    );
    expect(occurrence.single.startSlot, 9);
    expect(occurrence.single.endSlot, 11);
  });
}
