import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

class SnapshotInfo {
  final int id;
  final DateTime createdAt;

  const SnapshotInfo({required this.id, required this.createdAt});
}

class StorageException implements Exception {
  final String message;
  final Object? cause;

  const StorageException(this.message, [this.cause]);

  @override
  String toString() => cause == null
      ? 'StorageException: $message'
      : 'StorageException: $message ($cause)';
}

/// SQLite persistence with one versioned JSON state row and immutable
/// revisions. The domain JSON remains the single format for validation and
/// backup, while SQLite provides atomic writes and durable snapshots.
class StorageRepository {
  static const int _databaseVersion = 1;
  static const String _defaultFileName = 'course_schedule.sqlite';

  final String? path;
  Database? _databaseInstance;

  StorageRepository({this.path});

  Future<Database> _database() async {
    final existing = _databaseInstance;
    if (existing != null && existing.isOpen) return existing;
    final dbPath = path ?? '${await getDatabasesPath()}/$_defaultFileName';
    try {
      _databaseInstance = await openDatabase(
        dbPath,
        version: _databaseVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE schedule_state (
              id INTEGER PRIMARY KEY,
              schema_version INTEGER NOT NULL,
              payload TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE schedule_snapshots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              schema_version INTEGER NOT NULL,
              payload TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        },
      );
      return _databaseInstance!;
    } catch (error) {
      throw StorageException('unable to open schedule database', error);
    }
  }

  Future<ScheduleData> load() async {
    final db = await _database();
    try {
      final rows = await db.query(
        'schedule_state',
        where: 'id = ?',
        whereArgs: const [1],
        limit: 1,
      );
      if (rows.isEmpty) return ScheduleData.blank();
      final row = rows.single;
      final version = row['schema_version'];
      if (version is! int || version != ScheduleJson.schemaVersion) {
        throw StorageException(
            'unsupported current state schema version $version');
      }
      final payload = row['payload'];
      if (payload is! String) {
        throw const StorageException('current state payload is not text');
      }
      return ScheduleJson.decode(jsonDecode(payload));
    } on StorageException {
      rethrow;
    } catch (error) {
      throw StorageException('current schedule state is invalid', error);
    }
  }

  /// Validates before the transaction and atomically replaces the current
  /// state. This does not create a revision implicitly.
  Future<void> save(ScheduleData data) async {
    data.validate();
    final payload = jsonEncode(ScheduleJson.encode(data));
    final db = await _database();
    try {
      await db.transaction((txn) async {
        await txn.insert(
          'schedule_state',
          {
            'id': 1,
            'schema_version': ScheduleJson.schemaVersion,
            'payload': payload,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } catch (error) {
      throw StorageException('unable to save schedule state', error);
    }
  }

  Future<SnapshotInfo> snapshot([ScheduleData? data]) async {
    final value = data ?? await load();
    value.validate();
    final payload = jsonEncode(ScheduleJson.encode(value));
    final createdAt = DateTime.now().toUtc();
    final db = await _database();
    try {
      final id = await db.insert('schedule_snapshots', {
        'schema_version': ScheduleJson.schemaVersion,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
      });
      return SnapshotInfo(id: id, createdAt: createdAt);
    } catch (error) {
      throw StorageException('unable to create schedule snapshot', error);
    }
  }

  Future<List<SnapshotInfo>> listSnapshots() async {
    final db = await _database();
    try {
      final rows = await db.query(
        'schedule_snapshots',
        columns: const ['id', 'created_at'],
        orderBy: 'created_at DESC, id DESC',
      );
      return rows.map((row) {
        final id = row['id'];
        final created = row['created_at'];
        if (id is! int || created is! String) {
          throw const FormatException('invalid snapshot metadata');
        }
        final date = DateTime.tryParse(created);
        if (date == null) {
          throw FormatException('invalid snapshot timestamp $created');
        }
        return SnapshotInfo(id: id, createdAt: date.toUtc());
      }).toList(growable: false);
    } catch (error) {
      if (error is StorageException) rethrow;
      throw StorageException('unable to list schedule snapshots', error);
    }
  }

  /// Existing snapshots remain untouched when a revision is restored.
  Future<ScheduleData> restore(int snapshotId) async {
    if (snapshotId < 1) {
      throw ArgumentError.value(snapshotId, 'snapshotId', 'must be positive');
    }
    final db = await _database();
    try {
      final rows = await db.query(
        'schedule_snapshots',
        where: 'id = ?',
        whereArgs: [snapshotId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StorageException('snapshot $snapshotId does not exist');
      }
      final row = rows.single;
      final version = row['schema_version'];
      final payload = row['payload'];
      if (version is! int ||
          version != ScheduleJson.schemaVersion ||
          payload is! String) {
        throw StorageException(
            'snapshot $snapshotId has an unsupported or malformed schema');
      }
      final restored = ScheduleJson.decode(jsonDecode(payload));
      await save(restored);
      return restored;
    } on StorageException {
      rethrow;
    } catch (error) {
      throw StorageException(
          'snapshot $snapshotId is invalid and was not restored', error);
    }
  }

  Future<void> close() async {
    final db = _databaseInstance;
    _databaseInstance = null;
    if (db != null && db.isOpen) await db.close();
  }
}
