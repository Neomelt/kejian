import 'dart:convert';
import 'dart:typed_data';

import '../domain/models.dart';

const scheduleBackupFormat = 'kejian.schedule.backup';
const scheduleBackupVersion = 1;

Uint8List encodeScheduleBackupBytes(ScheduleData schedule) =>
    Uint8List.fromList(utf8.encode(encodeScheduleBackup(schedule)));

String encodeScheduleBackup(ScheduleData schedule) => jsonEncode({
      'format': scheduleBackupFormat,
      'version': scheduleBackupVersion,
      'schedule': schedule.toJson(),
    });

/// Restore a backup after validating its envelope and delegating field-level
/// validation to the domain model. Invalid backups fail loudly so a damaged
/// file can never silently replace the local timetable.
ScheduleData decodeScheduleBackup(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) throw const FormatException('备份不是 JSON 对象。');
  if (decoded['format'] != scheduleBackupFormat) {
    throw const FormatException('不是课间的备份文件。');
  }
  if (decoded['version'] != scheduleBackupVersion) {
    throw FormatException('不支持的备份版本：${decoded['version']}。');
  }
  final schedule = decoded['schedule'];
  if (schedule is! Map) throw const FormatException('备份缺少 schedule 数据。');
  try {
    return ScheduleJson.decode(Map<String, dynamic>.from(schedule));
  } catch (e) {
    throw FormatException('备份数据校验失败：$e');
  }
}

ScheduleData decodeScheduleBackupBytes(Uint8List bytes) =>
    decodeScheduleBackup(utf8.decode(bytes));
