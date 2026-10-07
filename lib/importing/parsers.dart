import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../domain/models.dart';
import 'ics.dart';
import 'import_result.dart';

/// Parse a supported timetable file. Extensions are intentionally strict:
/// `.csv`, `.xlsx`, and `.ics` are supported; old binary `.xls` is rejected
/// with an actionable message rather than being guessed at.
Future<ImportResult> parseScheduleFile(
  Uint8List bytes,
  String filename,
  Term term,
) async {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.csv')) {
    return parseCsv(bytes, term, sourceLabel: filename);
  }
  if (lower.endsWith('.xlsx')) {
    return parseXlsx(bytes, term, sourceLabel: filename);
  }
  if (lower.endsWith('.ics') || lower.endsWith('.ical')) {
    return parseIcs(bytes, term, sourceLabel: filename);
  }
  if (lower.endsWith('.xls')) {
    return ImportResult(
      courses: const [],
      diagnostics: const [
        ImportDiagnostic(message: '不支持旧版二进制 XLS，请在教务系统导出 XLSX 或 CSV。'),
      ],
      skippedRows: 0,
      sourceLabel: filename,
    );
  }
  return ImportResult(
    courses: const [],
    diagnostics: [
      ImportDiagnostic(message: '不支持的文件格式：$filename。请选择 CSV、XLSX 或 ICS。'),
    ],
    skippedRows: 0,
    sourceLabel: filename,
  );
}

ImportResult parseCsv(
  Uint8List bytes,
  Term term, {
  String sourceLabel = 'CSV',
}) {
  // 教务系统常用 UTF-8 with BOM；UTF-8 replacement is useful for a legacy
  // export and still results in a visible row diagnostic if its text is bad.
  final text =
      utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
  final rows = _parseCsvRows(text);
  return _parseRows(rows, term, sourceLabel: sourceLabel);
}

ImportResult parseXlsx(
  Uint8List bytes,
  Term term, {
  String sourceLabel = 'XLSX',
}) {
  try {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) {
      return ImportResult(
        courses: const [],
        diagnostics: const [ImportDiagnostic(message: 'XLSX 中没有可读取的工作表。')],
        skippedRows: 0,
        sourceLabel: sourceLabel,
      );
    }
    final table = workbook.tables.values.first;
    final rows = <List<String>>[];
    for (final row in table.rows) {
      rows.add(row.map((cell) => cell?.value?.toString() ?? '').toList());
    }
    return _parseRows(rows, term, sourceLabel: sourceLabel);
  } catch (e) {
    return ImportResult(
      courses: const [],
      diagnostics: [ImportDiagnostic(message: '无法读取 XLSX：$e')],
      skippedRows: 0,
      sourceLabel: sourceLabel,
    );
  }
}

ImportResult _parseRows(
  List<List<String>> rows,
  Term term, {
  required String sourceLabel,
}) {
  if (rows.isEmpty) {
    return ImportResult(
      courses: const [],
      diagnostics: const [ImportDiagnostic(message: '文件为空。')],
      skippedRows: 0,
      sourceLabel: sourceLabel,
    );
  }
  final diagnostics = <ImportDiagnostic>[];
  final header = rows.first.map(_headerKey).toList();
  int find(Set<String> names) {
    for (var i = 0; i < header.length; i++) {
      if (names.contains(header[i])) return i;
    }
    return -1;
  }

  final titleAt = find({
    'title',
    'course',
    'coursename',
    'name',
    '课程',
    '课程名称',
    '课程名',
  });
  final teacherAt = find({'teacher', 'lecturer', 'instructor', '教师', '任课教师'});
  final roomAt = find({'room', 'classroom', 'location', '教室', '上课地点', '上课教室'});
  final weekdayAt = find({'weekday', 'day', 'week', '星期', '周几', '上课星期'});
  final weeksAt = find({'weeks', 'weekrange', 'weekno', '周次', '上课周次', '教学周'});
  final slotAt = find({'slot', 'period', 'periods', '节次', '上课节次'});
  final startAt = find({'startslot', 'startperiod', '开始节次', '起始节次'});
  final endAt = find({'endslot', 'endperiod', '结束节次'});
  final colorAt = find({'color', '颜色'});

  if (titleAt < 0 || weekdayAt < 0 || (slotAt < 0 && startAt < 0)) {
    diagnostics.add(
      const ImportDiagnostic(message: '表头至少需要课程名称、星期和节次列；支持中文或英文列名。'),
    );
    return ImportResult(
      courses: const [],
      diagnostics: diagnostics,
      skippedRows: 0,
      sourceLabel: sourceLabel,
    );
  }

  final courses = <Course>[];
  final keys = <String>{};
  var skipped = 0;
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    String value(int index) =>
        index >= 0 && index < row.length ? row[index].trim() : '';
    final title = value(titleAt);
    if (title.isEmpty && row.every((v) => v.trim().isEmpty)) continue;
    final line = r + 1;
    if (title.isEmpty) {
      diagnostics.add(ImportDiagnostic(line: line, message: '课程名称为空。'));
      skipped++;
      continue;
    }
    final weekday = _parseWeekday(value(weekdayAt));
    if (weekday == null) {
      diagnostics.add(
        ImportDiagnostic(line: line, message: '无法识别星期：${value(weekdayAt)}。'),
      );
      skipped++;
      continue;
    }
    final slotsText =
        slotAt >= 0 ? value(slotAt) : '${value(startAt)}-${value(endAt)}';
    final slotRange = _parseSlotRange(slotsText);
    if (slotRange == null || slotRange.$1 < 1 || slotRange.$2 < slotRange.$1) {
      diagnostics.add(
        ImportDiagnostic(line: line, message: '无法识别节次：$slotsText。'),
      );
      skipped++;
      continue;
    }
    final weeksText = weeksAt >= 0 ? value(weeksAt) : '';
    final weeks = parseWeeks(weeksText, term.weekCount);
    if (weeks == null || weeks.isEmpty) {
      diagnostics.add(
        ImportDiagnostic(line: line, message: '无法识别周次：$weeksText。'),
      );
      skipped++;
      continue;
    }
    final teacher = teacherAt >= 0 ? value(teacherAt) : '';
    final room = roomAt >= 0 ? value(roomAt) : '';
    final color = colorAt >= 0
        ? _parseColor(value(colorAt), title)
        : stableColorForImport(title);
    final key = courseKeyForImport(
      term.id,
      title,
      teacher,
      room,
      weekday,
      slotRange.$1,
      slotRange.$2,
      weeks,
    );
    if (!keys.add(key)) {
      diagnostics.add(
        ImportDiagnostic(line: line, message: '与此前行重复，已合并。', isError: false),
      );
      continue;
    }
    courses.add(
      Course(
        id: 'import_${shortHashForImport(key)}',
        termId: term.id,
        title: title,
        teacher: teacher,
        room: room,
        weekday: weekday,
        startSlot: slotRange.$1,
        endSlot: slotRange.$2,
        weeks: weeks,
        color: color,
      ),
    );
  }
  return ImportResult(
    courses: courses,
    diagnostics: diagnostics,
    skippedRows: skipped,
    sourceLabel: sourceLabel,
  );
}

/// Parse common Chinese and English week expressions. Returns null for an
/// expression that cannot be represented exactly by a set of teaching weeks.
List<int>? parseWeeks(String raw, int weekCount) {
  final text =
      raw.trim().replaceAll(' ', '').replaceAll('—', '-').replaceAll('－', '-');
  if (text.isEmpty) return List<int>.generate(weekCount, (i) => i + 1);
  if (text.contains('单周') && text.contains('双周')) {
    return List<int>.generate(weekCount, (i) => i + 1);
  }
  if (text == '单周' || text == '单') {
    return [for (var i = 1; i <= weekCount; i += 2) i];
  }
  if (text == '双周' || text == '双') {
    return [for (var i = 2; i <= weekCount; i += 2) i];
  }
  // 教务系统常写成 `1-16周(单周)` / `1-16周（双）`.
  final oddOnly = RegExp(r'单(?:周)?').hasMatch(text);
  final evenOnly = RegExp(r'双(?:周)?').hasMatch(text);
  final rangeText = text.replaceAll(RegExp(r'[（(]?[单双](?:周)?[）)]?'), '');
  final result = <int>{};
  for (final part in rangeText.split(RegExp(r'[,，;；、]'))) {
    if (part.isEmpty) {
      continue;
    }
    final match =
        RegExp(r'^(\d+)\s*(?:[-~至到]\s*(\d+))?\s*周?$').firstMatch(part);
    if (match == null) return null;
    final from = int.parse(match.group(1)!);
    final to = match.group(2) == null ? from : int.parse(match.group(2)!);
    if (from < 1 || to < from || to > weekCount) return null;
    result.addAll(List<int>.generate(to - from + 1, (i) => from + i));
  }
  if (oddOnly) result.removeWhere((week) => week.isEven);
  if (evenOnly) result.removeWhere((week) => week.isOdd);
  final sorted = result.toList()..sort();
  return sorted;
}

String _headerKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-（）()\[\]：:/.]'), '');

int? _parseWeekday(String raw) {
  final text = raw.trim().toLowerCase();
  final numeric = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));
  if (numeric != null && numeric >= 1 && numeric <= 7) return numeric;
  const names = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
    'mon': 1,
    'monday': 1,
    'tue': 2,
    'tuesday': 2,
    'wed': 3,
    'wednesday': 3,
    'thu': 4,
    'thursday': 4,
    'fri': 5,
    'friday': 5,
    'sat': 6,
    'saturday': 6,
    'sun': 7,
    'sunday': 7,
  };
  for (final e in names.entries) {
    if (text == e.key || text == '周${e.key}' || text == '星期${e.key}') {
      return e.value;
    }
  }
  return null;
}

(int, int)? _parseSlotRange(String raw) {
  final numbers = RegExp(r'\d+')
      .allMatches(raw)
      .map((m) => int.parse(m.group(0)!))
      .toList();
  if (numbers.isEmpty) return null;
  if (numbers.length == 1) return (numbers.first, numbers.first);
  return (numbers.first, numbers[1]);
}

int _parseColor(String raw, String title) {
  if (raw.isEmpty) return stableColorForImport(title);
  final value = int.tryParse(raw.replaceFirst('#', ''), radix: 16);
  return value ?? stableColorForImport(title);
}

int stableColorForImport(String text) {
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

String courseKeyForImport(
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

String shortHashForImport(String text) {
  var hash = 2166136261;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}

List<List<String>> _parseCsvRows(String text) {
  // A small RFC 4180 parser avoids platform-dependent line splitting and
  // handles quoted commas/newlines, which occur in Chinese room names.
  final result = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((c == '\n' || c == '\r') && !quoted) {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((v) => v.isNotEmpty)) result.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.length > 0 || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((v) => v.isNotEmpty)) result.add(row);
  }
  return result;
}
