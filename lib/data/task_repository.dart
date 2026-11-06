import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';

import '../domain/task.dart';
import '../domain/task_backup.dart';
import '../domain/task_filter.dart';
import '../domain/task_reminder.dart';

class TaskCursor {
  const TaskCursor({required this.startedAt, required this.id});

  final DateTime startedAt;
  final String id;
}

class TaskPage {
  const TaskPage({required this.tasks, required this.hasMore, this.nextCursor});

  final List<Task> tasks;
  final bool hasMore;
  final TaskCursor? nextCursor;
}

class InitialTaskData {
  const InitialTaskData({
    required this.runningTasks,
    required this.completedPage,
    required this.taskNames,
    required this.colors,
    required this.customColors,
    required this.reminders,
  });

  final List<Task> runningTasks;
  final TaskPage completedPage;
  final List<String> taskNames;
  final Map<String, int> colors;
  final List<int> customColors;

  /// Reminder settings keyed by [taskColorKey].
  final Map<String, TaskReminder> reminders;
}

abstract interface class TaskRepository {
  Future<InitialTaskData> loadInitial({
    required int pageSize,
    TaskFilter filter = const TaskFilter(),
  });
  Future<TaskPage> loadCompletedPage({
    required int pageSize,
    TaskFilter filter = const TaskFilter(),
    TaskCursor? before,
  });
  Future<List<String>> loadTaskNames();
  Future<String?> loadThemeMode();
  Future<void> saveThemeMode(String mode);
  Future<String?> loadSetting(String key);
  Future<void> saveSetting(String key, String value);
  Future<void> deleteSetting(String key);
  Future<List<int>> loadCustomColors();
  Future<void> addCustomColor(int argb);
  Future<void> saveReminder(String nameKey, TaskReminder reminder);
  Future<void> deleteReminder(String nameKey);
  Stream<BackupEntry> exportBackupEntries();
  Future<void> restoreBackup(Stream<BackupEntry> entries);
  Future<void> saveTask(
    Task task, {
    String? colorKey,
    int? colorValue,
    bool clearColor = false,
  });
  Future<void> deleteTask(String id);
  Stream<Task> streamTasksNamed(String name, {DateTime? startedBefore});
}

class SqliteTaskRepository implements TaskRepository {
  SqliteTaskRepository({
    DatabaseFactory? factory,
    Future<String> Function()? databasePath,
  }) : _databaseFactory = factory ?? databaseFactory,
       _databasePath = databasePath ?? _defaultDatabasePath;

  static const _databaseName = 'kronos.db';
  final DatabaseFactory _databaseFactory;
  final Future<String> Function() _databasePath;
  Future<Database>? _database;

  Future<Database> get _db => _database ??= _openDatabase();

  Future<Database> _openDatabase() async {
    final path = await _databasePath();
    return _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              started_at TEXT NOT NULL,
              ended_at TEXT,
              notes TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.execute(
            'CREATE INDEX tasks_started_at_idx ON tasks(started_at DESC)',
          );
          await db.execute(
            'CREATE INDEX tasks_ended_at_idx ON tasks(ended_at)',
          );
          await _createPaginationIndexes(db);
          await db.execute('''
            CREATE TABLE task_colors (
              name_key TEXT PRIMARY KEY,
              argb INTEGER NOT NULL
            )
          ''');
          await _createSettingsTable(db);
          await _createCustomColorsTable(db);
          await _createAnalyticsIndexes(db);
          await _createRemindersTable(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createPaginationIndexes(db);
            await _createSettingsTable(db);
          }
          if (oldVersion < 3) {
            await db.execute(
              "ALTER TABLE tasks ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
            );
            await _createCustomColorsTable(db);
          }
          if (oldVersion < 4) {
            await _createAnalyticsIndexes(db);
          }
          if (oldVersion < 5) {
            await _migrateTimestampsToUtc(db);
          }
          if (oldVersion < 6) {
            await _createRemindersTable(db);
          }
        },
      ),
    );
  }

  static Future<void> _createPaginationIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS tasks_completed_cursor_idx '
      'ON tasks(ended_at, started_at DESC, id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS tasks_running_order_idx '
      'ON tasks(ended_at, started_at ASC, id ASC)',
    );
  }

  static Future<void> _createSettingsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createCustomColorsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_colors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        argb INTEGER NOT NULL UNIQUE
      )
    ''');
  }

  static Future<void> _createAnalyticsIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS tasks_name_analytics_idx '
      'ON tasks(name COLLATE NOCASE, started_at ASC, id ASC)',
    );
  }

  static Future<void> _createRemindersTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_reminders (
        name_key TEXT PRIMARY KEY,
        minutes INTEGER NOT NULL,
        repeats INTEGER NOT NULL,
        sound TEXT NOT NULL
      )
    ''');
  }

  static Future<String> _defaultDatabasePath() async {
    final directory = await getDatabasesPath();
    return paths.join(directory, _databaseName);
  }

  @override
  Future<InitialTaskData> loadInitial({
    required int pageSize,
    TaskFilter filter = const TaskFilter(),
  }) async {
    final db = await _db;
    final results = await Future.wait([
      db.query(
        'tasks',
        where: 'ended_at IS NULL',
        orderBy: 'started_at ASC, id ASC',
      ),
      loadCompletedPage(pageSize: pageSize, filter: filter),
      db.query('task_colors'),
      loadTaskNames(),
      loadCustomColors(),
      loadReminders(),
    ]);
    final runningRows = results[0] as List<Map<String, Object?>>;
    final completedPage = results[1] as TaskPage;
    final colorRows = results[2] as List<Map<String, Object?>>;
    final taskNames = results[3] as List<String>;
    final customColors = results[4] as List<int>;
    final reminders = results[5] as Map<String, TaskReminder>;
    final runningTasks = runningRows.map(_taskFromRow).toList();
    final colors = {
      for (final row in colorRows)
        row['name_key']! as String: row['argb']! as int,
    };
    return InitialTaskData(
      runningTasks: runningTasks,
      completedPage: completedPage,
      taskNames: taskNames,
      colors: colors,
      customColors: customColors,
      reminders: reminders,
    );
  }

  @override
  Future<TaskPage> loadCompletedPage({
    required int pageSize,
    TaskFilter filter = const TaskFilter(),
    TaskCursor? before,
  }) async {
    final db = await _db;
    final conditions = <String>['ended_at IS NOT NULL'];
    final whereArgs = <Object?>[];
    final query = filter.query.trim();
    if (query.isNotEmpty) {
      conditions.add('instr(lower(name), lower(?)) > 0');
      whereArgs.add(query);
    }
    if (filter.startedAfter case final startedAfter?) {
      conditions.add('started_at >= ?');
      whereArgs.add(_isoUtc(startedAfter));
    }
    if (filter.startedBefore case final startedBefore?) {
      conditions.add('started_at <= ?');
      whereArgs.add(_isoUtc(startedBefore));
    }
    if (before case final cursor?) {
      conditions.add('(started_at < ? OR (started_at = ? AND id < ?))');
      whereArgs
        ..add(_isoUtc(cursor.startedAt))
        ..add(_isoUtc(cursor.startedAt))
        ..add(cursor.id);
    }
    final rows = await db.query(
      'tasks',
      where: conditions.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'started_at DESC, id DESC',
      limit: pageSize + 1,
    );
    final hasMore = rows.length > pageSize;
    final pageRows = hasMore ? rows.take(pageSize).toList() : rows;
    final tasks = pageRows.map(_taskFromRow).toList();
    return TaskPage(
      tasks: tasks,
      hasMore: hasMore,
      nextCursor: hasMore && tasks.isNotEmpty
          ? TaskCursor(startedAt: tasks.last.startedAt, id: tasks.last.id)
          : null,
    );
  }

  @override
  Future<List<String>> loadTaskNames() async {
    final db = await _db;
    final rows = await db.query(
      'tasks',
      distinct: true,
      columns: ['name'],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map((row) => row['name']! as String).toList();
  }

  @override
  Future<String?> loadThemeMode() async {
    return loadSetting('theme_mode');
  }

  @override
  Future<String?> loadSetting(String key) async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  @override
  Future<void> saveThemeMode(String mode) async {
    await saveSetting('theme_mode', mode);
  }

  @override
  Future<void> saveSetting(String key, String value) async {
    final db = await _db;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteSetting(String key) async {
    final db = await _db;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<List<int>> loadCustomColors() async {
    final db = await _db;
    final rows = await db.query(
      'custom_colors',
      columns: ['argb'],
      orderBy: 'id ASC',
    );
    return rows.map((row) => row['argb']! as int).toList();
  }

  @override
  Future<void> addCustomColor(int argb) async {
    final db = await _db;
    await db.insert('custom_colors', {
      'argb': argb,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<Map<String, TaskReminder>> loadReminders() async {
    final db = await _db;
    final rows = await db.query('task_reminders', orderBy: 'name_key ASC');
    return {
      for (final row in rows) row['name_key']! as String: _reminderFromRow(row),
    };
  }

  @override
  Future<void> saveReminder(String nameKey, TaskReminder reminder) async {
    final db = await _db;
    await db.insert('task_reminders', {
      'name_key': nameKey,
      'minutes': reminder.minutes,
      'repeats': reminder.repeats ? 1 : 0,
      'sound': reminder.sound,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteReminder(String nameKey) async {
    final db = await _db;
    await db.delete(
      'task_reminders',
      where: 'name_key = ?',
      whereArgs: [nameKey],
    );
  }

  static TaskReminder _reminderFromRow(Map<String, Object?> row) =>
      TaskReminder(
        interval: Duration(minutes: row['minutes']! as int),
        repeats: row['repeats']! as int != 0,
        sound: row['sound']! as String,
      );

  @override
  Stream<BackupEntry> exportBackupEntries() async* {
    final db = await _db;
    yield BackupHeader(DateTime.now());
    final cursor = await db.queryCursor(
      'tasks',
      orderBy: 'started_at ASC, id ASC',
      bufferSize: 256,
    );
    try {
      while (await cursor.moveNext()) {
        yield BackupTaskEntry(_taskFromRow(cursor.current));
      }
    } finally {
      await cursor.close();
    }
    final colorRows = await db.query('task_colors', orderBy: 'name_key ASC');
    for (final row in colorRows) {
      yield BackupColorEntry(row['name_key']! as String, row['argb']! as int);
    }
    final customColorRows = await db.query(
      'custom_colors',
      columns: ['argb'],
      orderBy: 'id ASC',
    );
    for (final row in customColorRows) {
      yield BackupCustomColorEntry(row['argb']! as int);
    }
    for (final row in await db.query(
      'task_reminders',
      orderBy: 'name_key ASC',
    )) {
      yield BackupReminderEntry(
        row['name_key']! as String,
        _reminderFromRow(row),
      );
    }
  }

  @override
  Future<void> restoreBackup(Stream<BackupEntry> entries) async {
    final db = await _db;
    try {
      await db.transaction((transaction) async {
        await transaction.delete('tasks');
        await transaction.delete('task_colors');
        await transaction.delete('custom_colors');
        await transaction.delete('task_reminders');
        await for (final entry in entries) {
          switch (entry) {
            case BackupHeader():
              break;
            case BackupTaskEntry(:final task):
              await transaction.insert('tasks', {
                'id': task.id,
                'name': task.name,
                'started_at': _isoUtc(task.startedAt),
                'ended_at': task.endedAt == null
                    ? null
                    : _isoUtc(task.endedAt!),
                'notes': task.notes,
              });
            case BackupColorEntry(:final key, :final argb):
              await transaction.insert('task_colors', {
                'name_key': key,
                'argb': argb,
              });
            case BackupCustomColorEntry(:final argb):
              await transaction.insert('custom_colors', {'argb': argb});
            case BackupReminderEntry(:final key, :final reminder):
              await transaction.insert('task_reminders', {
                'name_key': key,
                'minutes': reminder.minutes,
                'repeats': reminder.repeats ? 1 : 0,
                'sound': reminder.sound,
              });
          }
        }
      });
    } on DatabaseException {
      throw const FormatException(
        'The backup could not be restored; it may contain duplicate tasks.',
      );
    }
  }

  @override
  Future<void> saveTask(
    Task task, {
    String? colorKey,
    int? colorValue,
    bool clearColor = false,
  }) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.insert('tasks', {
        'id': task.id,
        'name': task.name,
        'started_at': _isoUtc(task.startedAt),
        'ended_at': task.endedAt == null ? null : _isoUtc(task.endedAt!),
        'notes': task.notes,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (colorKey != null && colorValue != null) {
        await transaction.insert('task_colors', {
          'name_key': colorKey,
          'argb': colorValue,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      } else if (clearColor && colorKey != null) {
        await transaction.delete(
          'task_colors',
          where: 'name_key = ?',
          whereArgs: [colorKey],
        );
      }
    });
  }

  @override
  Future<void> deleteTask(String id) async {
    final db = await _db;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Stream<Task> streamTasksNamed(String name, {DateTime? startedBefore}) async* {
    final db = await _db;
    final where = startedBefore == null
        ? 'name = ? COLLATE NOCASE'
        : 'name = ? COLLATE NOCASE AND started_at <= ?';
    final whereArgs = startedBefore == null
        ? [name]
        : [name, _isoUtc(startedBefore)];
    final cursor = await db.queryCursor(
      'tasks',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'started_at ASC, id ASC',
      bufferSize: 128,
    );
    try {
      while (await cursor.moveNext()) {
        yield _taskFromRow(cursor.current);
      }
    } finally {
      await cursor.close();
    }
  }

  Future<void> close() async {
    final database = _database;
    if (database != null) {
      await (await database).close();
      _database = null;
    }
  }

  static Task _taskFromRow(Map<String, Object?> row) => Task(
    id: row['id']! as String,
    name: row['name']! as String,
    startedAt: DateTime.parse(row['started_at']! as String),
    endedAt: row['ended_at'] == null
        ? null
        : DateTime.parse(row['ended_at']! as String),
    notes: row['notes'] as String? ?? '',
  );

  /// ISO 8601 instant, always in UTC with the `Z` suffix.
  static String _isoUtc(DateTime at) => at.toUtc().toIso8601String();

  /// Rewrites legacy suffix-less local timestamps to UTC `Z` form.
  ///
  /// Rows written before schema v5 stored the device's local wall clock, so
  /// they were interpreted in the timezone of whatever device read them next.
  /// The conversion happens Dart-side: SQLite's datetime functions would
  /// double-shift the strings because they treat bare timestamps as UTC.
  static Future<void> _migrateTimestampsToUtc(DatabaseExecutor db) async {
    final rows = await db.query(
      'tasks',
      columns: ['id', 'started_at', 'ended_at'],
    );
    for (final row in rows) {
      final updates = <String, Object?>{};
      final startedAt = DateTime.tryParse(row['started_at']! as String);
      if (startedAt != null) updates['started_at'] = _isoUtc(startedAt);
      if (row['ended_at'] case final String endedAtValue) {
        final endedAt = DateTime.tryParse(endedAtValue);
        if (endedAt != null) updates['ended_at'] = _isoUtc(endedAt);
      }
      if (updates.isNotEmpty) {
        await db.update(
          'tasks',
          updates,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }
}
