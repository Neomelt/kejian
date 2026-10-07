import 'models.dart';

/// Returns the Monday containing [date], with the time part removed.
DateTime mondayOf(DateTime date) {
  final d = dateOnly(date);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// Returns the 1-based academic week for [date].
///
/// Values outside the term are intentionally retained: the week immediately
/// before the start Monday is 0, and dates two weeks before are -1.  This lets
/// callers distinguish an out-of-term date instead of silently clamping it.
int currentWeek(Term term, DateTime date) {
  final start = DateTime.utc(
    term.startMonday.year,
    term.startMonday.month,
    term.startMonday.day,
  );
  final day = dateOnly(date);
  final target = DateTime.utc(day.year, day.month, day.day);
  final dayDelta = target.difference(start).inDays;
  return _floorDiv(dayDelta, 7) + 1;
}

int _floorDiv(int value, int divisor) {
  if (value >= 0) return value ~/ divisor;
  return -(((-value) + divisor - 1) ~/ divisor);
}

/// Courses scheduled on one date in the active term, including date/slot/room
/// overrides.  A moved lesson is emitted on its replacement date only; a
/// cancellation emits nothing.
List<LessonOccurrence> occurrencesForDate(ScheduleData data, DateTime date) {
  final term = data.activeTerm;
  if (term == null) return const [];
  return _occurrencesForDateInTerm(data, term, date);
}

/// A lesson used by the schedule UI.
///
/// [occurrence] is a concrete lesson on [occurrence.date].  [isCurrentWeek]
/// is false for a course that is part of the timetable but is not taught in
/// that particular teaching week.  Keeping those lessons in the display
/// model lets the week view show the stable shape of a timetable while still
/// making alternate-week lessons visibly quiet.
class DisplayOccurrence {
  final LessonOccurrence occurrence;
  final bool isCurrentWeek;

  const DisplayOccurrence({
    required this.occurrence,
    required this.isCurrentWeek,
  });
}

/// Returns concrete lessons and quiet placeholders for the selected date.
///
/// The normal [occurrencesForDate] API intentionally returns only lessons
/// that take place on that date.  The schedule UI additionally needs to show
/// an every-other-week course when the current week is its off week.  This
/// helper adds those placeholders, while respecting cancellations and moved
/// lessons so a one-off change never creates a misleading card.
List<DisplayOccurrence> displayOccurrencesForDate(
  ScheduleData data,
  Term term,
  DateTime date,
) {
  final d = dateOnly(date);
  final actual = _occurrencesForDateInTerm(data, term, d);
  final result = <DisplayOccurrence>[
    for (final lesson in actual)
      DisplayOccurrence(occurrence: lesson, isCurrentWeek: true),
  ];
  final actualCourseIds = actual.map((item) => item.course.id).toSet();
  final week = currentWeek(term, d);
  if (week < 1 || week > term.weekCount) return result;

  final courses = data.courses.where((course) => course.termId == term.id);
  for (final course in courses) {
    if (actualCourseIds.contains(course.id) || course.weekday != d.weekday) {
      continue;
    }
    // A matching override either cancels this date or moves it elsewhere.
    // In both cases there should be no quiet placeholder at the old slot.
    final matching = data.overrides
        .where(
          (override) =>
              override.courseId == course.id &&
              dateKey(override.originalDate) == dateKey(d),
        )
        .firstOrNull;
    if (matching != null) continue;
    result.add(DisplayOccurrence(
      occurrence: _occurrence(course, d, null),
      isCurrentWeek: course.weeks.contains(week),
    ));
  }
  result.sort((a, b) {
    final bySlot = a.occurrence.startSlot.compareTo(b.occurrence.startSlot);
    if (bySlot != 0) return bySlot;
    final byActive =
        (b.isCurrentWeek ? 1 : 0).compareTo(a.isCurrentWeek ? 1 : 0);
    if (byActive != 0) return byActive;
    final byTitle =
        a.occurrence.course.title.compareTo(b.occurrence.course.title);
    return byTitle != 0
        ? byTitle
        : a.occurrence.course.id.compareTo(b.occurrence.course.id);
  });
  return result;
}

/// A group of lessons whose slot ranges overlap on the same date.
///
/// Groups are connected components, so a 1–2 lesson, a 2–3 lesson and a 3–4
/// lesson are presented together.  The UI can show [primary] in the compact
/// card and reveal every entry from [occurrences] on tap.
class OccurrenceGroup {
  final List<DisplayOccurrence> occurrences;

  OccurrenceGroup(Iterable<DisplayOccurrence> occurrences)
      : occurrences = List.unmodifiable(_sortGroup(occurrences)) {
    if (this.occurrences.isEmpty) {
      throw ArgumentError.value(
          occurrences, 'occurrences', 'must not be empty');
    }
  }

  DateTime get date => occurrences.first.occurrence.date;

  int get startSlot => occurrences
      .map((item) => item.occurrence.startSlot)
      .reduce((a, b) => a < b ? a : b);

  int get endSlot => occurrences
      .map((item) => item.occurrence.endSlot)
      .reduce((a, b) => a > b ? a : b);

  DisplayOccurrence get primary => occurrences.first;

  bool get hasOverlap => occurrences.length > 1;
}

/// Groups overlapping display occurrences by date and slot range.
List<OccurrenceGroup> groupOccurrencesByTime(
  Iterable<DisplayOccurrence> occurrences,
) {
  final byDate = <String, List<DisplayOccurrence>>{};
  for (final occurrence in occurrences) {
    byDate
        .putIfAbsent(dateKey(occurrence.occurrence.date), () => [])
        .add(occurrence);
  }
  final groups = <OccurrenceGroup>[];
  for (final entries in byDate.values) {
    final sorted = [...entries]..sort((a, b) {
        final bySlot = a.occurrence.startSlot.compareTo(b.occurrence.startSlot);
        if (bySlot != 0) return bySlot;
        final byEnd = a.occurrence.endSlot.compareTo(b.occurrence.endSlot);
        if (byEnd != 0) return byEnd;
        final byActive =
            (b.isCurrentWeek ? 1 : 0).compareTo(a.isCurrentWeek ? 1 : 0);
        if (byActive != 0) return byActive;
        final byTitle =
            a.occurrence.course.title.compareTo(b.occurrence.course.title);
        return byTitle != 0
            ? byTitle
            : a.occurrence.course.id.compareTo(b.occurrence.course.id);
      });
    var current = <DisplayOccurrence>[];
    var maxEnd = 0;
    for (final entry in sorted) {
      final start = entry.occurrence.startSlot;
      if (current.isNotEmpty && start > maxEnd) {
        groups.add(OccurrenceGroup(current));
        current = <DisplayOccurrence>[];
        maxEnd = 0;
      }
      current.add(entry);
      if (entry.occurrence.endSlot > maxEnd) maxEnd = entry.occurrence.endSlot;
    }
    if (current.isNotEmpty) groups.add(OccurrenceGroup(current));
  }
  groups.sort((a, b) {
    final byDate = dateKey(a.date).compareTo(dateKey(b.date));
    return byDate != 0 ? byDate : a.startSlot.compareTo(b.startSlot);
  });
  return groups;
}

List<DisplayOccurrence> _sortGroup(Iterable<DisplayOccurrence> values) {
  final sorted = [...values]..sort((a, b) {
      final byActive =
          (b.isCurrentWeek ? 1 : 0).compareTo(a.isCurrentWeek ? 1 : 0);
      if (byActive != 0) return byActive;
      final bySlot = a.occurrence.startSlot.compareTo(b.occurrence.startSlot);
      if (bySlot != 0) return bySlot;
      final byTitle =
          a.occurrence.course.title.compareTo(b.occurrence.course.title);
      return byTitle != 0
          ? byTitle
          : a.occurrence.course.id.compareTo(b.occurrence.course.id);
    });
  return sorted;
}

/// Returns all occurrences for [week] (1-based) in [term].  Unlike
/// [occurrencesForDate], this does not depend on activeTermId.
List<LessonOccurrence> occurrencesForWeek(
  ScheduleData data,
  Term term,
  int week,
) {
  if (week < 1 || week > term.weekCount) return const [];
  final monday = term.startMonday.add(Duration(days: (week - 1) * 7));
  return [
    for (var offset = 0; offset < 7; offset++)
      ..._occurrencesForDateInTerm(
        data,
        term,
        monday.add(Duration(days: offset)),
      ),
  ];
}

List<LessonOccurrence> _occurrencesForDateInTerm(
  ScheduleData data,
  Term term,
  DateTime date,
) {
  final d = dateOnly(date);
  final courses = data.courses.where((course) => course.termId == term.id);
  final byCourse = {for (final course in courses) course.id: course};
  final result = <LessonOccurrence>[];

  for (final course in byCourse.values) {
    final matching = data.overrides
        .where(
          (override) =>
              override.courseId == course.id &&
              dateKey(override.originalDate) == dateKey(d),
        )
        .firstOrNull;
    if (_scheduledOn(course, term, d)) {
      if (matching == null ||
          matching.date == null ||
          dateKey(matching.date!) == dateKey(d)) {
        if (matching?.cancelled != true) {
          result.add(_occurrence(course, d, matching));
        }
      }
    }

    // A replacement can change weekday/date.  Validate that its original
    // lesson really existed before exposing the replacement.
    for (final override in data.overrides.where(
      (item) =>
          item.courseId == course.id &&
          item.date != null &&
          dateKey(item.date!) == dateKey(d),
    )) {
      if (dateKey(override.originalDate) == dateKey(d) ||
          override.cancelled ||
          !_scheduledOn(course, term, override.originalDate)) {
        continue;
      }
      result.add(_occurrence(course, d, override));
    }
  }
  result.sort((a, b) {
    final bySlot = a.startSlot.compareTo(b.startSlot);
    return bySlot != 0 ? bySlot : a.course.title.compareTo(b.course.title);
  });
  return result;
}

bool _scheduledOn(Course course, Term term, DateTime date) {
  final d = dateOnly(date);
  if (d.weekday != course.weekday) return false;
  final week = currentWeek(term, d);
  return week >= 1 && week <= term.weekCount && course.weeks.contains(week);
}

LessonOccurrence _occurrence(
  Course course,
  DateTime date,
  LessonOverride? override,
) =>
    LessonOccurrence(
      course: course,
      date: date,
      startSlot: override?.startSlot ?? course.startSlot,
      endSlot: override?.endSlot ?? course.endSlot,
      room: override?.room ?? course.room,
      overrideId: override?.id,
    );

class ScheduleConflict {
  final LessonOccurrence first;
  final LessonOccurrence second;

  const ScheduleConflict(this.first, this.second);
}

/// Finds overlapping slot ranges in one day.  The helper intentionally reports
/// each pair and leaves presentation/deduplication to the caller.
List<ScheduleConflict> conflicts(Iterable<LessonOccurrence> occurrences) {
  final list = occurrences.toList(growable: false);
  final result = <ScheduleConflict>[];
  for (var i = 0; i < list.length; i++) {
    for (var j = i + 1; j < list.length; j++) {
      final left = list[i];
      final right = list[j];
      if (dateKey(left.date) != dateKey(right.date)) continue;
      if (left.startSlot <= right.endSlot && right.startSlot <= left.endSlot) {
        result.add(ScheduleConflict(left, right));
      }
    }
  }
  return result;
}

List<ScheduleConflict> conflictsForDate(
  Iterable<LessonOccurrence> occurrences,
) =>
    conflicts(occurrences);

List<ScheduleConflict> findConflicts(
  Iterable<LessonOccurrence> occurrences,
) =>
    conflicts(occurrences);

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
