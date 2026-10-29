import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/data/task_repository.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/domain/task_backup.dart';
import 'package:kronos/domain/task_filter.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'loads running tasks, paginates completed tasks, and stores settings',
    () async {
      final repository = SqliteTaskRepository(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      addTearDown(repository.close);

      final started = DateTime.utc(2020, 1, 1);
      for (var index = 0; index < 121; index++) {
        final start = started.add(Duration(minutes: index ~/ 2));
        await repository.saveTask(
          Task(
            id: 'completed-${index.toString().padLeft(3, '0')}',
            name: index.isEven ? 'Planning' : 'Review',
            startedAt: start,
            endedAt: start.add(const Duration(minutes: 20)),
          ),
        );
      }
      final running = Task(
        id: 'running-1',
        name: 'Planning',
        startedAt: DateTime.utc(2026, 10, 28, 9),
        notes: 'Discuss the roadmap\nCapture follow-up actions',
      );
      await repository.saveTask(
        running,
        colorKey: 'planning',
        colorValue: 0xFF123456,
      );
      await repository.addCustomColor(0xFFAB12CD);

      final initial = await repository.loadInitial(pageSize: 50);
      expect(initial.runningTasks.map((task) => task.id), [running.id]);
      expect(initial.runningTasks.single.notes, running.notes);
      expect(initial.completedPage.tasks, hasLength(50));
      expect(initial.completedPage.hasMore, isTrue);
      expect(initial.taskNames, containsAll(['Planning', 'Review']));
      expect(initial.colors['planning'], 0xFF123456);
      expect(initial.customColors, [0xFFAB12CD]);

      final loaded = [...initial.completedPage.tasks];
      var page = initial.completedPage;
      while (page.hasMore) {
        page = await repository.loadCompletedPage(
          pageSize: 50,
          before: page.nextCursor,
        );
        loaded.addAll(page.tasks);
      }
      expect(loaded, hasLength(121));
      expect(loaded.map((task) => task.id).toSet(), hasLength(121));
      expect(
        loaded.map((task) => task.startedAt),
        orderedEquals(
          [...loaded.map((task) => task.startedAt)]
            ..sort((a, b) => b.compareTo(a)),
        ),
      );

      expect(await repository.loadThemeMode(), isNull);
      await repository.saveThemeMode('dark');
      expect(await repository.loadThemeMode(), 'dark');
      await repository.deleteTask(running.id);
      expect(
        (await repository.loadInitial(pageSize: 50)).runningTasks,
        isEmpty,
      );
    },
  );

  test('removes the shared color when no color is selected', () async {
    final repository = SqliteTaskRepository(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    addTearDown(repository.close);
    final task = Task(
      id: 'task-1',
      name: 'Planning',
      startedAt: DateTime.utc(2026),
    );

    await repository.saveTask(
      task,
      colorKey: 'planning',
      colorValue: 0xFF123456,
    );
    await repository.saveTask(task, colorKey: 'planning', clearColor: true);

    expect((await repository.loadInitial(pageSize: 10)).colors, isEmpty);
  });

  test(
    'exports and restores tasks without overwriting device settings',
    () async {
      final repository = SqliteTaskRepository(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      addTearDown(repository.close);
      final startedAt = DateTime.utc(2025, 4, 1, 10);
      await repository.saveTask(
        Task(
          id: 'original',
          name: 'Planning',
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 40)),
          notes: 'Original notes',
        ),
        colorKey: 'planning',
        colorValue: 0xFF123456,
      );
      await repository.addCustomColor(0xFFABCDEF);
      await repository.saveThemeMode('dark');
      await repository.saveSetting('automatic_backups_enabled', 'true');

      final exported = await repository.exportBackup();
      final decoded = TaskBackup.fromJson(
        jsonDecode(jsonEncode(exported.toJson())),
      );
      await repository.deleteTask('original');
      await repository.saveThemeMode('light');
      await repository.restoreBackup(decoded);

      final restored = await repository.loadInitial(pageSize: 10);
      expect(restored.completedPage.tasks.single.id, 'original');
      expect(restored.completedPage.tasks.single.notes, 'Original notes');
      expect(restored.colors['planning'], 0xFF123456);
      expect(restored.customColors, [0xFFABCDEF]);
      expect(await repository.loadThemeMode(), 'light');
      expect(await repository.loadSetting('automatic_backups_enabled'), 'true');
    },
  );

  test(
    'exports and transactionally restores the complete task dataset',
    () async {
      final repository = SqliteTaskRepository(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      addTearDown(repository.close);
      final startedAt = DateTime.utc(2025, 4, 1, 10);
      await repository.saveTask(
        Task(
          id: 'original',
          name: 'Planning',
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 40)),
          notes: 'Original notes',
        ),
        colorKey: 'planning',
        colorValue: 0xFF123456,
      );
      await repository.addCustomColor(0xFFABCDEF);

      final backup = await repository.exportBackup();
      expect(backup.tasks.single.notes, 'Original notes');

      await repository.saveTask(
        Task(id: 'later', name: 'Different', startedAt: DateTime.utc(2026)),
      );
      await repository.restoreBackup(backup);

      final restored = await repository.loadInitial(pageSize: 10);
      expect(restored.runningTasks, isEmpty);
      expect(restored.completedPage.tasks.map((task) => task.id), ['original']);
      expect(restored.completedPage.tasks.single.notes, 'Original notes');
      expect(restored.colors['planning'], 0xFF123456);
      expect(restored.customColors, [0xFFABCDEF]);
    },
  );

  test(
    'filters task names and started-at bounds through cursor pages',
    () async {
      final repository = SqliteTaskRepository(
        factory: databaseFactoryFfi,
        databasePath: () async => inMemoryDatabasePath,
      );
      addTearDown(repository.close);
      final started = DateTime.utc(2025, 5, 1);
      for (var index = 0; index < 80; index++) {
        final taskStarted = started.add(Duration(minutes: index));
        await repository.saveTask(
          Task(
            id: 'task-${index.toString().padLeft(3, '0')}',
            name: index.isEven ? 'Planning' : 'Review',
            startedAt: taskStarted,
            endedAt: taskStarted.add(const Duration(minutes: 5)),
          ),
        );
      }

      const filter = TaskFilter(query: 'PLAN');
      final first = await repository.loadCompletedPage(
        pageSize: 10,
        filter: filter,
      );
      expect(first.tasks, hasLength(10));
      expect(first.hasMore, isTrue);
      expect(first.tasks.every((task) => task.name == 'Planning'), isTrue);

      final second = await repository.loadCompletedPage(
        pageSize: 10,
        filter: filter,
        before: first.nextCursor,
      );
      expect(second.tasks, hasLength(10));
      expect(
        second.tasks.every(
          (task) => task.startedAt.isBefore(first.tasks.last.startedAt),
        ),
        isTrue,
      );

      final bounded = await repository.loadCompletedPage(
        pageSize: 50,
        filter: TaskFilter(
          query: 'planning',
          startedAfter: started.add(const Duration(minutes: 20)),
          startedBefore: started.add(const Duration(minutes: 30)),
        ),
      );
      expect(bounded.tasks, hasLength(6));
      expect(
        bounded.tasks.every(
          (task) =>
              !task.startedAt.isBefore(
                started.add(const Duration(minutes: 20)),
              ) &&
              !task.startedAt.isAfter(started.add(const Duration(minutes: 30))),
        ),
        isTrue,
      );
    },
  );

  test(
    'upgrades an existing version 2 database without losing tasks',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kronos-migration-',
      );
      final databasePath = paths.join(directory.path, 'kronos.db');
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE tasks (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              started_at TEXT NOT NULL,
              ended_at TEXT
            )
          ''');
            await db.execute('''
            CREATE TABLE task_colors (
              name_key TEXT PRIMARY KEY,
              argb INTEGER NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE app_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          },
        ),
      );
      await oldDatabase.insert('tasks', {
        'id': 'before-upgrade',
        'name': 'Planning',
        'started_at': DateTime.utc(2025).toIso8601String(),
        'ended_at': null,
      });
      await oldDatabase.close();

      final repository = SqliteTaskRepository(
        factory: databaseFactoryFfi,
        databasePath: () async => databasePath,
      );
      try {
        final initial = await repository.loadInitial(pageSize: 10);
        expect(initial.runningTasks.single.id, 'before-upgrade');
        expect(initial.runningTasks.single.notes, '');
        await repository.addCustomColor(0xFF123456);
        expect(await repository.loadCustomColors(), [0xFF123456]);
      } finally {
        await repository.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
