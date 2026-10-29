import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/data/task_repository.dart';
import 'package:kronos/domain/task.dart';
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
      );
      await repository.saveTask(
        running,
        colorKey: 'planning',
        colorValue: 0xFF123456,
      );

      final initial = await repository.loadInitial(pageSize: 50);
      expect(initial.runningTasks.map((task) => task.id), [running.id]);
      expect(initial.completedPage.tasks, hasLength(50));
      expect(initial.completedPage.hasMore, isTrue);
      expect(initial.taskNames, containsAll(['Planning', 'Review']));
      expect(initial.colors['planning'], 0xFF123456);

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
}
