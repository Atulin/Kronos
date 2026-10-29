import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/data/task_repository.dart';
import 'package:kronos/domain/task.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('stores tasks and shared colors in SQLite', () async {
    final repository = SqliteTaskRepository(
      factory: databaseFactoryFfi,
      databasePath: () async => inMemoryDatabasePath,
    );
    addTearDown(repository.close);
    final started = DateTime(2026, 10, 28, 9);
    final running = Task(
      id: 'running-1',
      name: 'Planning',
      startedAt: DateTime(2026),
    );
    final completed = Task(
      id: 'completed-1',
      name: 'Planning',
      startedAt: started,
      endedAt: started.add(const Duration(minutes: 45)),
    );

    await repository.saveTask(
      running,
      colorKey: 'planning',
      colorValue: 0xFF123456,
    );
    await repository.saveTask(completed);
    final loaded = await repository.load();

    expect(
      loaded.tasks.map((task) => task.id),
      containsAll([running.id, completed.id]),
    );
    expect(
      loaded.tasks.firstWhere((task) => task.id == 'completed-1').endedAt,
      started.add(const Duration(minutes: 45)),
    );
    expect(loaded.colors['planning'], 0xFF123456);

    await repository.deleteTask(running.id);
    expect((await repository.load()).tasks, hasLength(1));
  });
}
