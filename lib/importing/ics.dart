import 'dart:convert';
import 'dart:typed_data';

import '../domain/models.dart';
import 'import_result.dart';

ImportResult parseIcs(
  Uint8List bytes,
  Term term, {
  String sourceLabel = 'ICS',
}) {
  final raw = utf8.decode(bytes, allowMalformed: true);
  final lines = _unfold(raw);
  final diagnostics = <ImportDiagnostic>[];
  final courses = <Course>[];
  final keys = <String>{};
  final events = <Map<String, String>>[];
  Map<String, String>? current;
  var eventLine = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final upper = line.toUpperCase();
    if (upper == 'BEGIN:VEVENT') {
      current = <String, String>{};
      eventLine = i + 1;
      continue;
    }
    if (upper == 'END:VEVENT') {
      if (current != null) events.add(current);
      current = null;
      continue;
    }
    if (current == null) continue;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final left = line.substring(0, colon);
    final key = left.split(';').first.toUpperCase();
    current[key] = _unescapeIcs(line.substring(colon + 1));
    current['__line'] = '$eventLine';
    // Preserve DTSTART parameters (TZID/value) for validation.
    if (key == 'DTSTART' || key == 'DTEND') current['__${key}_left'] = left;
  }
  if (events.isEmpty) {
    diagnostics.add(const ImportDiagnostic(message: 'ICS 中没有 VEVENT。'));
  }
  for (final event in events) {
    final line = int.tryParse(event['__line'] ?? '');
    final summary = (event['SUMMARY'] ?? '').trim();
    final dtStart = _parseIcsDate(event['DTSTART'], event['__DTSTART_left']);
    final dtEnd = _parseIcsDate(event['DTEND'], event['__DTEND_left']);
    if (summary.isEmpty || dtStart == null || dtEnd == null) {
      final hasTimeZone =
          (event['__DTSTART_left']?.toUpperCase().contains('TZID=') ?? false) ||
              (event['__DTEND_left']?.toUpperCase().contains('TZID=') ??
                  false) ||
              (event['DTSTART']?.endsWith('Z') ?? false) ||
              (event['DTEND']?.endsWith('Z') ?? false);
      diagnostics.add(ImportDiagnostic(
        line: line,
        message: hasTimeZone
            ? '暂不支持带 TZID/UTC 时区的 DTSTART/DTEND，请导出本地浮动时间的 ICS。'
            : 'VEVENT 缺少课程名称或可解析的 DTSTART/DTEND。',
      ));
      continue;
    }
    if (dtEnd.isBefore(dtStart) || !_sameCalendarDate(dtStart, dtEnd)) {
      diagnostics.add(
        ImportDiagnostic(line: line, message: '不支持跨日课程，已跳过该 VEVENT。'),
      );
      continue;
    }
    final recurrence = _expandRecurrence(event, dtStart, term);
    if (recurrence == null) {
      diagnostics.add(
        ImportDiagnostic(line: line, message: 'RRULE 不是可安全转换的每周重复规则，已跳过。'),
      );
      continue;
    }
    final slotRange = _findSlots(
      term,
      dtStart.hour * 60 + dtStart.minute,
      dtEnd.hour * 60 + dtEnd.minute,
    );
    if (slotRange == null) {
      diagnostics.add(
        ImportDiagnostic(
          line: line,
          message: '课程时间 ${_hhmm(dtStart)}-${_hhmm(dtEnd)} 与学期节次不匹配，已跳过。',
        ),
      );
      continue;
    }
    final teacher = _extractTeacher(event['DESCRIPTION'] ?? '');
    final room = (event['LOCATION'] ?? '').trim();
    final key = _courseKey(
      term.id,
      summary,
      teacher,
      room,
      recurrence.weekday,
      slotRange.$1,
      slotRange.$2,
      recurrence.weeks,
    );
    if (!keys.add(key)) continue;
    courses.add(
      Course(
        id: 'import_${_shortHash(key)}',
        termId: term.id,
        title: summary,
        teacher: teacher,
        room: room,
        weekday: recurrence.weekday,
        startSlot: slotRange.$1,
        endSlot: slotRange.$2,
        weeks: recurrence.weeks,
        color: _stableColor(summary),
      ),
    );
  }
  return ImportResult(
    courses: courses,
    diagnostics: diagnostics,
    skippedRows: events.length - courses.length,
    sourceLabel: sourceLabel,
  );
}

List<String> _unfold(String raw) {
  final physical =
      raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final result = <String>[];
  for (final line in physical) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && result.isNotEmpty) {
      result[result.length - 1] += line.substring(1);
    } else {
      result.add(line);
    }
  }
  return result;
}

String _unescapeIcs(String value) => value
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', '\\');

DateTime? _parseIcsDate(String? value, String? left) {
  if (value == null || value.isEmpty) return null;
  // A phone may be in a different timezone from the campus. Converting TZID
  // or UTC correctly requires a timezone database and a user-selected campus
  // zone; interpreting it as local time would silently move a lesson.
  if (value.endsWith('Z') || (left?.toUpperCase().contains('TZID=') ?? false)) {
    return null;
  }
  if (left?.toUpperCase().contains('VALUE=DATE') == true || value.length == 8) {
    if (!RegExp(r'^\d{8}$').hasMatch(value)) return null;
    return DateTime(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
    );
  }
  final match = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$')
      .firstMatch(value);
  if (match == null) return null;
  // Keep the wall-clock value. A timetable's slot definitions are local to
  // the school; converting a TZID to the phone's zone would shift a class.
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

({int weekday, List<int> weeks})? _expandRecurrence(
  Map<String, String> event,
  DateTime start,
  Term term,
) {
  final raw = event['RRULE'];
  final firstWeek = _termWeek(start, term);
  if (firstWeek == null) return null;
  if (raw == null || raw.trim().isEmpty) {
    return (weekday: start.weekday, weeks: [firstWeek]);
  }
  final fields = <String, String>{};
  for (final item in raw.split(';')) {
    final p = item.split('=');
    if (p.length == 2) {
      fields[p[0].toUpperCase()] = p[1];
    }
  }
  if (fields['FREQ']?.toUpperCase() != 'WEEKLY' ||
      (fields['INTERVAL'] != null && fields['INTERVAL'] != '1')) {
    return null;
  }
  final byDay = fields['BYDAY'];
  if (byDay != null && byDay != _icalDay(start.weekday)) return null;
  final weeks = <int>[];
  final count = int.tryParse(fields['COUNT'] ?? '');
  if (fields.containsKey('COUNT') && count == null) return null;
  DateTime? until;
  if (fields['UNTIL'] != null) {
    until = _parseIcsDate(fields['UNTIL'], null);
    if (until == null) return null;
  }
  for (var week = firstWeek; week <= term.weekCount; week++) {
    final date = term.startMonday.add(Duration(days: (week - firstWeek) * 7));
    if (until != null && date.isAfter(until)) break;
    if (count != null && weeks.length >= count) break;
    weeks.add(week);
  }
  return weeks.isEmpty ? null : (weekday: start.weekday, weeks: weeks);
}

int? _termWeek(DateTime date, Term term) {
  final day = DateTime(date.year, date.month, date.day);
  final monday = DateTime(
    term.startMonday.year,
    term.startMonday.month,
    term.startMonday.day,
  );
  final days = day.difference(monday).inDays;
  if (days < 0 || days >= term.weekCount * 7) return null;
  return days ~/ 7 + 1;
}

(int, int)? _findSlots(Term term, int startMinute, int endMinute) {
  final matches = term.slots
      .where(
        (slot) =>
            slot.startMinutes <= startMinute && slot.endMinutes >= endMinute,
      )
      .toList();
  if (matches.isNotEmpty) return (matches.first.index, matches.first.index);
  final covered = term.slots
      .where(
        (slot) =>
            slot.startMinutes >= startMinute && slot.endMinutes <= endMinute,
      )
      .toList();
  if (covered.isEmpty) return null;
  return (covered.first.index, covered.last.index);
}

String _icalDay(int weekday) =>
    const ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'][weekday - 1];
String _hhmm(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _extractTeacher(String description) {
  final match = RegExp(
    r'(?:教师|老师|Teacher)\s*[:：]\s*([^\n;；]+)',
    caseSensitive: false,
  ).firstMatch(description);
  return match?.group(1)?.trim() ?? '';
}

bool _sameCalendarDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _courseKey(
  String termId,
  String title,
  String teacher,
  String room,
  int weekday,
  int start,
  int end,
  List<int> weeks,
) =>
    '$termId|${title.trim().toLowerCase()}|${teacher.trim().toLowerCase()}|${room.trim().toLowerCase()}|$weekday|$start|$end|${weeks.join(',')}';

String _shortHash(String text) {
  var hash = 2166136261;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}

int _stableColor(String text) {
  var hash = 2166136261;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  const palette = [
    0xFF5E6AD2,
    0xFF0F766E,
    0xFFD97706,
    0xFFDB2777,
    0xFF2563EB,
    0xFF7C3AED,
  ];
  return palette[hash % palette.length];
}
