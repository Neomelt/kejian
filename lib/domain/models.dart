/// Core, platform-independent schedule models.
///
/// These classes deliberately contain no Flutter or database dependencies.  All
/// date fields have date semantics (the time part is discarded at construction)
/// and are encoded as `yyyy-MM-dd` by [ScheduleJson].
library;

enum ThemeMode { system, light, dark }

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool isDateOnly(DateTime value) =>
    value.hour == 0 &&
    value.minute == 0 &&
    value.second == 0 &&
    value.millisecond == 0 &&
    value.microsecond == 0;

String dateKey(DateTime value) {
  final d = dateOnly(value);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

class TimeSlot {
  final int index;
  final int startMinutes;
  final int endMinutes;

  TimeSlot({
    required this.index,
    required this.startMinutes,
    required this.endMinutes,
  }) {
    if (index < 1) {
      throw ArgumentError.value(index, 'index', 'must be at least 1');
    }
    if (startMinutes < 0 || startMinutes >= 24 * 60) {
      throw ArgumentError.value(
        startMinutes,
        'startMinutes',
        'must be in 0..1439',
      );
    }
    if (endMinutes <= startMinutes || endMinutes > 24 * 60) {
      throw ArgumentError.value(
        endMinutes,
        'endMinutes',
        'must be after start and at most 1440',
      );
    }
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
      };

  @override
  bool operator ==(Object other) =>
      other is TimeSlot &&
      other.index == index &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(index, startMinutes, endMinutes);
}

class Term {
  final String id;
  final String name;
  final DateTime startMonday;
  final int weekCount;
  final List<TimeSlot> slots;

  Term({
    required this.id,
    required this.name,
    required DateTime startMonday,
    required this.weekCount,
    required List<TimeSlot> slots,
  })  : startMonday = dateOnly(startMonday),
        slots = List.unmodifiable(slots) {
    _requireText(id, 'id');
    _requireText(name, 'name');
    if (!isDateOnly(startMonday) ||
        this.startMonday.weekday != DateTime.monday) {
      throw ArgumentError.value(
        startMonday,
        'startMonday',
        'must be a date at Monday',
      );
    }
    if (weekCount < 1) {
      throw ArgumentError.value(weekCount, 'weekCount', 'must be at least 1');
    }
    _validateSlots(this.slots);
  }

  static List<TimeSlot> defaultSlots() => [
        TimeSlot(index: 1, startMinutes: 480, endMinutes: 525),
        TimeSlot(index: 2, startMinutes: 535, endMinutes: 580),
        TimeSlot(index: 3, startMinutes: 600, endMinutes: 645),
        TimeSlot(index: 4, startMinutes: 655, endMinutes: 700),
        TimeSlot(index: 5, startMinutes: 720, endMinutes: 765),
        TimeSlot(index: 6, startMinutes: 775, endMinutes: 820),
        TimeSlot(index: 7, startMinutes: 840, endMinutes: 885),
        TimeSlot(index: 8, startMinutes: 895, endMinutes: 940),
        TimeSlot(index: 9, startMinutes: 960, endMinutes: 1005),
        TimeSlot(index: 10, startMinutes: 1015, endMinutes: 1060),
        TimeSlot(index: 11, startMinutes: 1080, endMinutes: 1125),
        TimeSlot(index: 12, startMinutes: 1135, endMinutes: 1180),
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startMonday': dateKey(startMonday),
        'weekCount': weekCount,
        'slots': slots.map((slot) => slot.toJson()).toList(growable: false),
      };

  @override
  bool operator ==(Object other) =>
      other is Term &&
      other.id == id &&
      other.name == name &&
      other.startMonday == startMonday &&
      other.weekCount == weekCount &&
      _listEquals(other.slots, slots);

  @override
  int get hashCode =>
      Object.hash(id, name, startMonday, weekCount, Object.hashAll(slots));
}

class Course {
  final String id;
  final String termId;
  final String title;
  final String teacher;
  final String room;
  final int weekday;
  final int startSlot;
  final int endSlot;
  final List<int> weeks;
  final int color;
  final double? credits;

  Course({
    required this.id,
    required this.termId,
    required this.title,
    required this.teacher,
    required this.room,
    required this.weekday,
    required this.startSlot,
    required this.endSlot,
    required List<int> weeks,
    required this.color,
    this.credits,
  }) : weeks = List.unmodifiable(List<int>.from(weeks)) {
    _requireText(id, 'id');
    _requireText(termId, 'termId');
    _requireText(title, 'title');
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError.value(weekday, 'weekday', 'must be in 1..7');
    }
    if (startSlot < 1 || endSlot < startSlot) {
      throw ArgumentError('startSlot/endSlot must describe a non-empty range');
    }
    if (this.weeks.any((week) => week < 1) ||
        !_strictlyIncreasing(this.weeks)) {
      throw ArgumentError.value(
        weeks,
        'weeks',
        'must be unique, sorted, positive week numbers',
      );
    }
    if (credits != null && (!credits!.isFinite || credits! < 0)) {
      throw ArgumentError.value(
          credits, 'credits', 'must be finite and non-negative');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'termId': termId,
        'title': title,
        'teacher': teacher,
        'room': room,
        'weekday': weekday,
        'startSlot': startSlot,
        'endSlot': endSlot,
        'weeks': weeks,
        'color': color,
        if (credits != null) 'credits': credits,
      };

  @override
  bool operator ==(Object other) =>
      other is Course &&
      other.id == id &&
      other.termId == termId &&
      other.title == title &&
      other.teacher == teacher &&
      other.room == room &&
      other.weekday == weekday &&
      other.startSlot == startSlot &&
      other.endSlot == endSlot &&
      _listEquals(other.weeks, weeks) &&
      other.color == color &&
      other.credits == credits;

  @override
  int get hashCode => Object.hash(
        id,
        termId,
        title,
        teacher,
        room,
        weekday,
        startSlot,
        endSlot,
        Object.hashAll(weeks),
        color,
        credits,
      );
}

class LessonOverride {
  final String id;
  final String courseId;
  final DateTime originalDate;
  final bool cancelled;
  final DateTime? date;
  final int? startSlot;
  final int? endSlot;
  final String? room;

  LessonOverride({
    required this.id,
    required this.courseId,
    required DateTime originalDate,
    required this.cancelled,
    DateTime? date,
    this.startSlot,
    this.endSlot,
    this.room,
  })  : originalDate = dateOnly(originalDate),
        date = date == null ? null : dateOnly(date) {
    _requireText(id, 'id');
    _requireText(courseId, 'courseId');
    if (!isDateOnly(originalDate)) {
      throw ArgumentError.value(
        originalDate,
        'originalDate',
        'must be date-only',
      );
    }
    if (date != null && !isDateOnly(date)) {
      throw ArgumentError.value(date, 'date', 'must be date-only');
    }
    final start = startSlot;
    final end = endSlot;
    if (start != null && start < 1) {
      throw ArgumentError.value(start, 'startSlot', 'must be at least 1');
    }
    if (end != null && end < 1) {
      throw ArgumentError.value(end, 'endSlot', 'must be at least 1');
    }
    if (start != null && end != null && end < start) {
      throw ArgumentError(
        'startSlot/endSlot must describe a non-empty range',
      );
    }
    if (room != null && room!.trim().isEmpty) {
      throw ArgumentError.value(room, 'room', 'must not be empty when present');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'originalDate': dateKey(originalDate),
        'cancelled': cancelled,
        'date': date == null ? null : dateKey(date!),
        'startSlot': startSlot,
        'endSlot': endSlot,
        'room': room,
      };

  @override
  bool operator ==(Object other) =>
      other is LessonOverride &&
      other.id == id &&
      other.courseId == courseId &&
      other.originalDate == originalDate &&
      other.cancelled == cancelled &&
      other.date == date &&
      other.startSlot == startSlot &&
      other.endSlot == endSlot &&
      other.room == room;

  @override
  int get hashCode => Object.hash(
        id,
        courseId,
        originalDate,
        cancelled,
        date,
        startSlot,
        endSlot,
        room,
      );
}

class LessonOccurrence {
  final Course course;
  final DateTime date;
  final int startSlot;
  final int endSlot;
  final String room;
  final String? overrideId;

  LessonOccurrence({
    required this.course,
    required DateTime date,
    required this.startSlot,
    required this.endSlot,
    required this.room,
    this.overrideId,
  }) : date = dateOnly(date) {
    if (startSlot < 1 || endSlot < startSlot) {
      throw ArgumentError('invalid occurrence slot range');
    }
  }
}

class AppSettings {
  final ThemeMode darkMode;
  final bool remindersEnabled;
  final int reminderMinutes;

  AppSettings({
    this.darkMode = ThemeMode.system,
    this.remindersEnabled = false,
    this.reminderMinutes = 10,
  }) {
    if (reminderMinutes < 0 || reminderMinutes > 24 * 60) {
      throw ArgumentError.value(
        reminderMinutes,
        'reminderMinutes',
        'must be in 0..1440',
      );
    }
  }

  Map<String, dynamic> toJson() => {
        'darkMode': darkMode.name,
        'remindersEnabled': remindersEnabled,
        'reminderMinutes': reminderMinutes,
      };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.darkMode == darkMode &&
      other.remindersEnabled == remindersEnabled &&
      other.reminderMinutes == reminderMinutes;

  @override
  int get hashCode => Object.hash(darkMode, remindersEnabled, reminderMinutes);
}

class ScheduleData {
  final List<Term> terms;
  final String? activeTermId;
  final List<Course> courses;
  final List<LessonOverride> overrides;
  final AppSettings settings;

  ScheduleData({
    required List<Term> terms,
    required this.activeTermId,
    required List<Course> courses,
    required List<LessonOverride> overrides,
    required this.settings,
  })  : terms = List.unmodifiable(terms),
        courses = List.unmodifiable(courses),
        overrides = List.unmodifiable(overrides) {
    validate();
  }

  factory ScheduleData.blank() => ScheduleData(
        terms: const [],
        activeTermId: null,
        courses: const [],
        overrides: const [],
        settings: AppSettings(),
      );

  factory ScheduleData.fromJson(Object? source) => ScheduleJson.decode(source);

  factory ScheduleData.initial() => ScheduleData.blank();

  /// An explicit, deterministic fixture useful for previews and manual testing.
  factory ScheduleData.sample() {
    final term = Term(
      id: 'sample-2026-spring',
      name: '2026 春季学期',
      startMonday: DateTime(2026, 2, 23),
      weekCount: 18,
      slots: Term.defaultSlots(),
    );
    return ScheduleData(
      terms: [term],
      activeTermId: term.id,
      courses: [
        Course(
          id: 'sample-math',
          termId: term.id,
          title: '高等数学',
          teacher: '示例教师',
          room: 'A101',
          weekday: 1,
          startSlot: 1,
          endSlot: 2,
          weeks: List.generate(18, (i) => i + 1),
          color: 0xFF5B8FF9,
        ),
        Course(
          id: 'sample-english',
          termId: term.id,
          title: '大学英语',
          teacher: '示例教师',
          room: 'B201',
          weekday: 3,
          startSlot: 3,
          endSlot: 4,
          weeks: const [1, 3, 5, 7, 9, 11, 13, 15, 17],
          color: 0xFF61DDAA,
        ),
      ],
      overrides: const [],
      settings: AppSettings(),
    );
  }

  Term? get activeTerm =>
      terms.where((term) => term.id == activeTermId).firstOrNull;

  void validate() {
    _unique(terms.map((term) => term.id), 'term id');
    _unique(courses.map((course) => course.id), 'course id');
    _unique(overrides.map((override) => override.id), 'override id');
    final termById = {for (final term in terms) term.id: term};
    if (activeTermId != null && !termById.containsKey(activeTermId)) {
      throw FormatException('activeTermId does not refer to a term');
    }
    for (final course in courses) {
      final term = termById[course.termId];
      if (term == null) {
        throw FormatException(
          'course ${course.id} refers to missing term ${course.termId}',
        );
      }
      final slotIndexes = term.slots.map((slot) => slot.index).toSet();
      for (var slot = course.startSlot; slot <= course.endSlot; slot++) {
        if (!slotIndexes.contains(slot)) {
          throw FormatException('course ${course.id} uses a missing slot');
        }
      }
      if (course.weeks.any((week) => week > term.weekCount)) {
        throw FormatException(
          'course ${course.id} uses a week outside its term',
        );
      }
    }
    final courseIds = courses.map((course) => course.id).toSet();
    final overrideKeys = <String>{};
    for (final override in overrides) {
      if (!courseIds.contains(override.courseId)) {
        throw FormatException(
          'override ${override.id} refers to missing course',
        );
      }
      final key = '${override.courseId}|${dateKey(override.originalDate)}';
      if (!overrideKeys.add(key)) {
        throw FormatException('duplicate override for $key');
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': ScheduleJson.schemaVersion,
        'terms': terms.map((term) => term.toJson()).toList(growable: false),
        'activeTermId': activeTermId,
        'courses':
            courses.map((course) => course.toJson()).toList(growable: false),
        'overrides': overrides
            .map((override) => override.toJson())
            .toList(growable: false),
        'settings': settings.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is ScheduleData &&
      other.activeTermId == activeTermId &&
      other.settings == settings &&
      _listEquals(other.terms, terms) &&
      _listEquals(other.courses, courses) &&
      _listEquals(other.overrides, overrides);

  @override
  int get hashCode => Object.hash(
        activeTermId,
        Object.hashAll(terms),
        Object.hashAll(courses),
        Object.hashAll(overrides),
        settings,
      );
}

class ScheduleJson {
  static const int schemaVersion = 1;

  static Map<String, dynamic> encode(ScheduleData data) => data.toJson();

  static ScheduleData decode(Object? source) {
    if (source is! Map) {
      throw const FormatException('schedule JSON must be an object');
    }
    return _decodeMap(_map(source, 'schedule'));
  }

  static ScheduleData _decodeMap(Map<String, dynamic> map) {
    final version = _int(map, 'schemaVersion');
    if (version != schemaVersion) {
      throw FormatException('unsupported schedule schema version $version');
    }
    final terms = _list(map, 'terms', (item) {
      final m = _map(item, 'term');
      return Term(
        id: _string(m, 'id'),
        name: _string(m, 'name'),
        startMonday: _date(m, 'startMonday'),
        weekCount: _int(m, 'weekCount'),
        slots: _list(m, 'slots', (slot) {
          final s = _map(slot, 'slot');
          return TimeSlot(
            index: _int(s, 'index'),
            startMinutes: _int(s, 'startMinutes'),
            endMinutes: _int(s, 'endMinutes'),
          );
        }),
      );
    });
    final courses = _list(map, 'courses', (item) {
      final m = _map(item, 'course');
      return Course(
        id: _string(m, 'id'),
        termId: _string(m, 'termId'),
        title: _string(m, 'title'),
        teacher: _text(m, 'teacher'),
        room: _text(m, 'room'),
        weekday: _int(m, 'weekday'),
        startSlot: _int(m, 'startSlot'),
        endSlot: _int(m, 'endSlot'),
        weeks: _list(m, 'weeks', (item) => _asInt(item, 'week')),
        color: _int(m, 'color'),
        credits:
            m['credits'] == null ? null : _asDouble(m['credits'], 'credits'),
      );
    });
    final overrides = _list(map, 'overrides', (item) {
      final m = _map(item, 'override');
      return LessonOverride(
        id: _string(m, 'id'),
        courseId: _string(m, 'courseId'),
        originalDate: _date(m, 'originalDate'),
        cancelled: _bool(m, 'cancelled'),
        date: m['date'] == null ? null : _date(m, 'date'),
        startSlot:
            m['startSlot'] == null ? null : _asInt(m['startSlot'], 'startSlot'),
        endSlot: m['endSlot'] == null ? null : _asInt(m['endSlot'], 'endSlot'),
        room: m['room'] == null ? null : _asString(m['room'], 'room'),
      );
    });
    final active = map['activeTermId'];
    if (active != null && active is! String) {
      throw const FormatException('activeTermId must be a string or null');
    }
    final settingsMap = _map(map['settings'], 'settings');
    final mode = _string(settingsMap, 'darkMode');
    final darkMode =
        ThemeMode.values.where((item) => item.name == mode).firstOrNull;
    if (darkMode == null) throw FormatException('invalid darkMode $mode');
    final settings = AppSettings(
      darkMode: darkMode,
      remindersEnabled: _bool(settingsMap, 'remindersEnabled'),
      reminderMinutes: _int(settingsMap, 'reminderMinutes'),
    );
    return ScheduleData(
      terms: terms,
      activeTermId: active as String?,
      courses: courses,
      overrides: overrides,
      settings: settings,
    );
  }

  static Map<String, dynamic> _map(Object? value, String name) {
    if (value is! Map) throw FormatException('$name must be an object');
    if (value.keys.any((key) => key is! String)) {
      throw FormatException('$name object keys must be strings');
    }
    return Map<String, dynamic>.from(value);
  }

  static List<T> _list<T>(
    Map<String, dynamic> map,
    String key,
    T Function(Object?) parse,
  ) {
    final value = map[key];
    if (value is! List) throw FormatException('$key must be an array');
    return List<T>.unmodifiable(value.map(parse));
  }

  static String _string(Map<String, dynamic> map, String key) =>
      _asString(map[key], key);
  static String _text(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String) throw FormatException('$key must be a string');
    return value;
  }

  static String _asString(Object? value, String key) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  static int _int(Map<String, dynamic> map, String key) =>
      _asInt(map[key], key);
  static int _asInt(Object? value, String key) {
    if (value is! int) throw FormatException('$key must be an integer');
    return value;
  }

  static double _asDouble(Object? value, String key) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    throw FormatException('$key must be a number');
  }

  static bool _bool(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! bool) throw FormatException('$key must be a boolean');
    return value;
  }

  static DateTime _date(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw FormatException('$key must be yyyy-MM-dd');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || dateKey(parsed) != value) {
      throw FormatException('$key is not a valid date');
    }
    return parsed;
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _validateSlots(List<TimeSlot> slots) {
  if (slots.isEmpty) throw ArgumentError('a term needs at least one time slot');
  if (!_strictlyIncreasing(slots.map((slot) => slot.index).toList())) {
    throw ArgumentError('slot indexes must be unique and sorted');
  }
}

bool _strictlyIncreasing(List<int> values) {
  for (var i = 1; i < values.length; i++) {
    if (values[i] <= values[i - 1]) return false;
  }
  return true;
}

void _unique(Iterable<String> values, String label) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) throw FormatException('duplicate $label: $value');
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
