import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'data/storage_repository.dart';
import 'domain/models.dart';
import 'domain/schedule_helpers.dart';
import 'importing/backup.dart';
import 'importing/import_result.dart';
import 'importing/parsers.dart';
import 'services/reminder_service.dart';

class ScheduleController extends ChangeNotifier {
  ScheduleController({
    StorageRepository? repository,
    ReminderService? reminderService,
    DateTime Function()? clock,
  })  : _repository = repository ?? StorageRepository(),
        _reminders = reminderService ?? const ReminderService(),
        _clock = clock ?? DateTime.now,
        _focusedDate = dateOnly((clock ?? DateTime.now)());

  final StorageRepository _repository;
  final ReminderService _reminders;
  final DateTime Function() _clock;
  Future<void> _writeQueue = Future<void>.value();
  Future<void> _reminderQueue = Future<void>.value();

  ScheduleData _data = ScheduleData.blank();
  DateTime _focusedDate;
  bool _ready = false;
  bool _saving = false;
  bool _storageBlocked = false;
  String? _lastError;
  ReminderStatus _notificationStatus = ReminderStatus.unavailable;

  ScheduleData get data => _data;
  DateTime get focusedDate => _focusedDate;
  bool get ready => _ready;
  bool get saving => _saving;
  bool get storageBlocked => _storageBlocked;
  String? get lastError => _lastError;
  Term? get activeTerm => _data.activeTerm;
  ReminderStatus get notificationStatus => _notificationStatus;

  Future<void> init() async {
    if (_ready) return;
    try {
      final loaded = await _repository.load();
      _data = loaded;
      _storageBlocked = false;
      _lastError = null;
      final term = loaded.activeTerm;
      if (term != null) _focusedDate = _weekStartForDate(term, _clock());
    } catch (error) {
      // Never replace an unreadable database with sample/blank data on disk.
      // Keep a usable in-memory blank view and expose the blocked state so UI
      // can offer export/recovery instead of silently destroying user data.
      _storageBlocked = true;
      _lastError = '本地数据读取失败，未覆盖原数据：$error';
      _data = ScheduleData.blank();
      _focusedDate = dateOnly(_clock());
    } finally {
      _ready = true;
      notifyListeners();
      await _refreshReminders();
    }
  }

  Future<void> onForeground() => _refreshReminders();

  void setFocusedDate(DateTime date) {
    _focusedDate = dateOnly(date);
    notifyListeners();
  }

  void shiftWeek(int amount) {
    final term = activeTerm;
    if (term == null) {
      setFocusedDate(_focusedDate.add(Duration(days: amount * 7)));
      return;
    }
    final current = currentWeek(term, _focusedDate);
    final target = (current + amount).clamp(1, term.weekCount);
    setFocusedDate(
      term.startMonday.add(Duration(days: (target - 1) * 7)),
    );
  }

  void goToCurrentWeek() {
    final term = activeTerm;
    setFocusedDate(term == null ? _clock() : _weekStartForDate(term, _clock()));
  }

  Future<void> setData(ScheduleData value) => _mutate(() async {
        await _repository.save(value);
        _publish(value);
      });

  Future<void> saveTerm(Term term, {bool makeActive = true}) => _mutate(
        () async {
          final terms = [
            ..._data.terms.where((item) => item.id != term.id),
            term
          ];
          final next = ScheduleData(
            terms: terms,
            activeTermId: makeActive ? term.id : _data.activeTermId,
            courses: _data.courses,
            overrides: _data.overrides,
            settings: _data.settings,
          );
          await _repository.save(next);
          _publish(next);
        },
      );

  Future<void> selectTerm(String termId) => _mutate(() async {
        if (!_data.terms.any((term) => term.id == termId)) {
          throw ArgumentError.value(termId, 'termId', 'term does not exist');
        }
        final next = ScheduleData(
          terms: _data.terms,
          activeTermId: termId,
          courses: _data.courses,
          overrides: _data.overrides,
          settings: _data.settings,
        );
        await _repository.save(next);
        _publish(next);
      });

  Future<void> deleteTerm(String termId) => _mutate(() async {
        final remainingTerms =
            _data.terms.where((term) => term.id != termId).toList();
        if (remainingTerms.length == _data.terms.length) return;
        final courseIds = _data.courses
            .where((course) => course.termId == termId)
            .map((course) => course.id)
            .toSet();
        final next = ScheduleData(
          terms: remainingTerms,
          activeTermId: _data.activeTermId == termId
              ? (remainingTerms.isEmpty ? null : remainingTerms.first.id)
              : _data.activeTermId,
          courses: _data.courses
              .where((course) => !courseIds.contains(course.id))
              .toList(),
          overrides: _data.overrides
              .where((item) => !courseIds.contains(item.courseId))
              .toList(),
          settings: _data.settings,
        );
        await _repository.save(next);
        _publish(next);
      });

  Future<void> saveCourse(Course course) => _mutate(() async {
        final matches = _data.courses.where((item) => item.id == course.id);
        final previous = matches.isEmpty ? null : matches.first;
        final scheduleChanged = previous != null &&
            (previous.termId != course.termId ||
                previous.weekday != course.weekday ||
                previous.startSlot != course.startSlot ||
                previous.endSlot != course.endSlot ||
                previous.weeks.join(',') != course.weeks.join(','));
        final nextCourses = [
          ..._data.courses.where((item) => item.id != course.id),
          course,
        ];
        final next = ScheduleData(
          terms: _data.terms,
          activeTermId: _data.activeTermId,
          courses: nextCourses,
          overrides: scheduleChanged
              ? _data.overrides
                  .where((item) => item.courseId != course.id)
                  .toList()
              : _data.overrides,
          settings: _data.settings,
        );
        await _repository.save(next);
        _publish(next);
      });

  Future<void> deleteCourse(String id) => _mutate(() async {
        final next = ScheduleData(
          terms: _data.terms,
          activeTermId: _data.activeTermId,
          courses: _data.courses.where((course) => course.id != id).toList(),
          overrides:
              _data.overrides.where((item) => item.courseId != id).toList(),
          settings: _data.settings,
        );
        await _repository.save(next);
        _publish(next);
      });

  Future<void> saveOverride(LessonOverride override) => _mutate(() async {
        final nextOverrides = [
          ..._data.overrides.where(
            (item) =>
                item.id != override.id &&
                !(item.courseId == override.courseId &&
                    dateKey(item.originalDate) ==
                        dateKey(override.originalDate)),
          ),
          override,
        ];
        final next = ScheduleData(
          terms: _data.terms,
          activeTermId: _data.activeTermId,
          courses: _data.courses,
          overrides: nextOverrides,
          settings: _data.settings,
        );
        await _repository.save(next);
        _publish(next);
      });

  Future<void> removeOverride(String id) => _mutate(() async {
        final next = ScheduleData(
          terms: _data.terms,
          activeTermId: _data.activeTermId,
          courses: _data.courses,
          overrides: _data.overrides.where((item) => item.id != id).toList(),
          settings: _data.settings,
        );
        await _repository.save(next);
        _publish(next);
      });

  Future<ImportResult> importSchedule(PlatformFile file) async {
    final term = activeTerm;
    if (term == null) {
      return const ImportResult(
        courses: [],
        diagnostics: [ImportDiagnostic(message: '请先创建一个学期。')],
        skippedRows: 0,
        sourceLabel: 'import',
      );
    }
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      return const ImportResult(
        courses: [],
        diagnostics: [ImportDiagnostic(message: '无法读取所选文件。')],
        skippedRows: 0,
        sourceLabel: 'import',
      );
    }
    return parseScheduleFile(bytes, file.name, term);
  }

  Future<void> commitImportedCourses(
    List<Course> courses, {
    bool replace = false,
  }) =>
      _mutate(() async {
        final term = activeTerm;
        if (term == null) throw StateError('请先创建一个学期。');
        if (replace) await _repository.snapshot(_data);

        final existing = _data.courses
            .where((course) => !replace || course.termId != term.id)
            .toList();
        final existingKeys = existing.map(_courseContentKey).toSet();
        final usedIds = existing.map((course) => course.id).toSet();
        final imported = <Course>[];
        for (final source in courses.where((item) => item.termId == term.id)) {
          final key = _courseContentKey(source);
          if (!existingKeys.add(key)) continue;
          var value = source;
          var suffix = 1;
          while (!usedIds.add(value.id)) {
            value = _copyCourseWithId(source, '${source.id}_$suffix');
            suffix++;
          }
          imported.add(value);
        }
        final preservedOverrides = replace
            ? _data.overrides
                .where(
                  (item) => !_data.courses.any(
                    (course) =>
                        course.termId == term.id && course.id == item.courseId,
                  ),
                )
                .toList()
            : _data.overrides;
        final next = ScheduleData(
          terms: _data.terms,
          activeTermId: _data.activeTermId,
          courses: [...existing, ...imported],
          overrides: preservedOverrides,
          settings: _data.settings,
        );
        await _repository.save(next);
        _publish(next);
      });

  ScheduleData previewRestoreJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['format'] == scheduleBackupFormat) {
      return decodeScheduleBackup(text);
    }
    return ScheduleJson.decode(decoded);
  }

  Future<void> restoreJson(String text) =>
      restoreData(previewRestoreJson(text));

  Future<void> restoreData(ScheduleData value) => setData(value);

  Future<SnapshotInfo> createSnapshot() =>
      _writeQueue.then((_) => _repository.snapshot(_data));

  Future<List<SnapshotInfo>> listSnapshots() => _repository.listSnapshots();

  Future<void> restoreSnapshot(int snapshotId) => _mutate(() async {
        final restored = await _repository.restore(snapshotId);
        _publish(restored);
      });

  /// Explicit sample action. It maps the sample term to the current Monday so
  /// the preview opens around today without seeding fresh installations.
  Future<void> loadSample() => _mutate(() async {
        final sample = ScheduleData.sample();
        final source = sample.terms.single;
        final mappedTerm = Term(
          id: source.id,
          name: source.name,
          startMonday: mondayOf(_clock()),
          weekCount: source.weekCount,
          slots: source.slots,
        );
        final mapped = ScheduleData(
          terms: [mappedTerm],
          activeTermId: mappedTerm.id,
          courses: sample.courses,
          overrides: const [],
          settings: _data.settings,
        );
        await _repository.save(mapped);
        _publish(mapped);
      });

  Future<void> updateSettings({
    ThemeMode? themeMode,
    bool? remindersEnabled,
    int? reminderMinutes,
  }) =>
      _mutate(() async {
        final next = ScheduleData(
          terms: _data.terms,
          activeTermId: _data.activeTermId,
          courses: _data.courses,
          overrides: _data.overrides,
          settings: AppSettings(
            darkMode: themeMode ?? _data.settings.darkMode,
            remindersEnabled:
                remindersEnabled ?? _data.settings.remindersEnabled,
            reminderMinutes: reminderMinutes ?? _data.settings.reminderMinutes,
          ),
        );
        await _repository.save(next);
        _publish(next);
      });

  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(ScheduleJson.encode(_data));

  Future<bool> requestReminderPermission() async {
    final granted = await _reminders.requestPermission();
    await _refreshReminders();
    return granted;
  }

  Future<void> refreshReminders() => _refreshReminders();

  Future<void> _refreshReminders() {
    final result = _reminderQueue.then((_) => _refreshRemindersNow());
    _reminderQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _refreshRemindersNow() async {
    try {
      final current = await _reminders.status();
      if (!_data.settings.remindersEnabled) {
        await _reminders.cancel();
        _notificationStatus = current;
      } else if (!current.authorized) {
        _notificationStatus = current;
      } else {
        final plans = _buildReminderPlans();
        final count = await _reminders.schedule(plans);
        _notificationStatus = ReminderStatus(
          supported: current.supported,
          permission: current.permission,
          pendingCount: count,
          nextAt: plans.isEmpty ? null : plans.first.timestamp,
          message: current.message,
        );
      }
      notifyListeners();
    } catch (error) {
      _notificationStatus = ReminderStatus(
        supported: false,
        permission: ReminderPermission.unknown,
        message: '$error',
      );
      notifyListeners();
    }
  }

  List<ReminderPlan> _buildReminderPlans() {
    final term = activeTerm;
    if (term == null) return const [];
    final now = _clock();
    final end = now.add(const Duration(days: 63));
    final plans = <ReminderPlan>[];
    for (var date = dateOnly(now);
        !date.isAfter(dateOnly(end)) && plans.length < 63;
        date = date.add(const Duration(days: 1))) {
      final slots = {for (final slot in term.slots) slot.index: slot};
      for (final occurrence in occurrencesForDate(_data, date)) {
        final slot = slots[occurrence.startSlot];
        if (slot == null) continue;
        final start = DateTime(
          date.year,
          date.month,
          date.day,
        ).add(Duration(minutes: slot.startMinutes));
        final timestamp = start.subtract(
          Duration(minutes: _data.settings.reminderMinutes),
        );
        if (!timestamp.isAfter(now)) continue;
        plans.add(
          ReminderPlan(
            id: _reminderId(occurrence),
            title: occurrence.course.title,
            body: [
              if (occurrence.room.trim().isNotEmpty) occurrence.room,
              if (occurrence.course.teacher.trim().isNotEmpty)
                occurrence.course.teacher,
            ].join(' · '),
            timestamp: timestamp,
          ),
        );
        if (plans.length >= 63) break;
      }
    }
    plans.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return plans.take(63).toList(growable: false);
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _writeQueue.then<T>((_) async {
      _saving = true;
      notifyListeners();
      try {
        return await operation();
      } catch (error) {
        _lastError = '$error';
        notifyListeners();
        rethrow;
      } finally {
        _saving = false;
        notifyListeners();
      }
    });
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  void _publish(ScheduleData value) {
    final oldActiveId = _data.activeTermId;
    _data = value;
    _storageBlocked = false;
    _lastError = null;
    final term = value.activeTerm;
    if (term != null && oldActiveId != value.activeTermId) {
      _focusedDate = _weekStartForDate(term, _clock());
    }
    notifyListeners();
    unawaited(_refreshReminders());
  }

  /// Returns the Monday for the phone's current academic week.  Dates before
  /// or after the term are clamped to the first/last teaching week so opening
  /// the app never lands on an empty out-of-term grid.
  DateTime _weekStartForDate(Term term, DateTime date) {
    final week = currentWeek(term, date).clamp(1, term.weekCount);
    return term.startMonday.add(Duration(days: (week - 1) * 7));
  }

  static int _reminderId(LessonOccurrence occurrence) {
    var hash = 2166136261;
    final text =
        '${occurrence.course.id}|${dateKey(occurrence.date)}|${occurrence.startSlot}|${occurrence.endSlot}';
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static String _courseContentKey(Course course) => [
        course.termId,
        course.title,
        course.teacher,
        course.room,
        course.weekday,
        course.startSlot,
        course.endSlot,
        course.weeks.join(','),
      ].join('|');

  static Course _copyCourseWithId(Course course, String id) => Course(
        id: id,
        termId: course.termId,
        title: course.title,
        teacher: course.teacher,
        room: course.room,
        weekday: course.weekday,
        startSlot: course.startSlot,
        endSlot: course.endSlot,
        weeks: course.weeks,
        color: course.color,
        credits: course.credits,
      );
}
