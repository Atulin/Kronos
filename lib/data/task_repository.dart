import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';

import '../domain/task.dart';

typedef TaskData = ({List<Task> tasks, Map<String, int> colors});

abstract interface class TaskRepository {
  Future<TaskData> load();
  Future<void> saveTask(Task task, {String? colorKey, int? colorValue});
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
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              started_at TEXT NOT NULL,
              ended_at TEXT
            )
          ''');
          await db.execute(
            'CREATE INDEX tasks_started_at_idx ON tasks(started_at DESC)',
          );
          await db.execute(
            'CREATE INDEX tasks_ended_at_idx ON tasks(ended_at)',
          );
          await db.execute('''
            CREATE TABLE task_colors (
              name_key TEXT PRIMARY KEY,
              argb INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
  }

  static Future<String> _defaultDatabasePath() async {
    final directory = await getDatabasesPath();
    return paths.join(directory, _databaseName);
  }

  @override
  Future<TaskData> load() async {
    final db = await _db;
    final taskRows = await db.query('tasks', orderBy: 'started_at DESC');
    final colorRows = await db.query('task_colors');
    final tasks = taskRows
        .map(
          (row) => Task(
            id: row['id']! as String,
            name: row['name']! as String,
            startedAt: DateTime.parse(row['started_at']! as String),
            endedAt: row['ended_at'] == null
                ? null
                : DateTime.parse(row['ended_at']! as String),
          ),
        )
        .toList();
    final colors = {
      for (final row in colorRows)
        row['name_key']! as String: row['argb']! as int,
    };
    return (tasks: tasks, colors: colors);
  }

  @override
  Future<void> saveTask(Task task, {String? colorKey, int? colorValue}) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.insert('tasks', {
        'id': task.id,
        'name': task.name,
        'started_at': task.startedAt.toIso8601String(),
        'ended_at': task.endedAt?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (colorKey != null && colorValue != null) {
        await transaction.insert('task_colors', {
          'name_key': colorKey,
          'argb': colorValue,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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
}
