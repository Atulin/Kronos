import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';

import '../domain/task.dart';

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
  });

  final List<Task> runningTasks;
  final TaskPage completedPage;
  final List<String> taskNames;
  final Map<String, int> colors;
  final List<int> customColors;
}

abstract interface class TaskRepository {
  Future<InitialTaskData> loadInitial({required int pageSize});
  Future<TaskPage> loadCompletedPage({
    required int pageSize,
    TaskCursor? before,
  });
  Future<List<String>> loadTaskNames();
  Future<String?> loadThemeMode();
  Future<void> saveThemeMode(String mode);
  Future<List<int>> loadCustomColors();
  Future<void> addCustomColor(int argb);
  Future<void> saveTask(
    Task task, {
    String? colorKey,
    int? colorValue,
    bool clearColor = false,
  });
  Future<void> deleteTask(String id);
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
        version: 3,
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

  static Future<String> _defaultDatabasePath() async {
    final directory = await getDatabasesPath();
    return paths.join(directory, _databaseName);
  }

  @override
  Future<InitialTaskData> loadInitial({required int pageSize}) async {
    final db = await _db;
    final results = await Future.wait([
      db.query(
        'tasks',
        where: 'ended_at IS NULL',
        orderBy: 'started_at ASC, id ASC',
      ),
      loadCompletedPage(pageSize: pageSize),
      db.query('task_colors'),
      loadTaskNames(),
      loadCustomColors(),
    ]);
    final runningRows = results[0] as List<Map<String, Object?>>;
    final completedPage = results[1] as TaskPage;
    final colorRows = results[2] as List<Map<String, Object?>>;
    final taskNames = results[3] as List<String>;
    final customColors = results[4] as List<int>;
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
    );
  }

  @override
  Future<TaskPage> loadCompletedPage({
    required int pageSize,
    TaskCursor? before,
  }) async {
    final db = await _db;
    final where = before == null
        ? 'ended_at IS NOT NULL'
        : 'ended_at IS NOT NULL AND '
              '(started_at < ? OR (started_at = ? AND id < ?))';
    final whereArgs = before == null
        ? null
        : [
            before.startedAt.toIso8601String(),
            before.startedAt.toIso8601String(),
            before.id,
          ];
    final rows = await db.query(
      'tasks',
      where: where,
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
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['theme_mode'],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  @override
  Future<void> saveThemeMode(String mode) async {
    final db = await _db;
    await db.insert('app_settings', {
      'key': 'theme_mode',
      'value': mode,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
        'started_at': task.startedAt.toIso8601String(),
        'ended_at': task.endedAt?.toIso8601String(),
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
}
