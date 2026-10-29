import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/data/task_repository.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/presentation/task_view_model.dart';

void main() {
  late _MemoryTaskRepository repository;
  late TaskViewModel viewModel;

  setUp(() async {
    repository = _MemoryTaskRepository();
    viewModel = TaskViewModel(repository);
    await viewModel.load();
  });

  tearDown(() => viewModel.dispose());

  test('starts and stops tasks, persisting both states', () async {
    await viewModel.startTask('Planning');
    expect(viewModel.runningTasks, hasLength(1));
    expect(repository.tasks.single.isRunning, isTrue);

    await viewModel.stopTask(viewModel.runningTasks.single);
    expect(viewModel.runningTasks, isEmpty);
    expect(viewModel.completedTasks, hasLength(1));
    expect(repository.tasks.single.isRunning, isFalse);
  });

  test(
    'suggestions match without case sensitivity and prioritize prefixes',
    () async {
      await viewModel.startTask('Write report');
      await viewModel.startTask('Monthly writing');

      expect(viewModel.suggestionsFor('Wri'), [
        'Write report',
        'Monthly writing',
      ]);
    },
  );

  test('updates a task and shares its chosen color by name', () async {
    await viewModel.startTask('Planning');
    final task = viewModel.runningTasks.single;
    const color = Color(0xFF123456);

    await viewModel.updateTask(task.copyWith(name: 'Review'), color: color);

    expect(viewModel.runningTasks.single.name, 'Review');
    expect(viewModel.colorFor('Review'), color);
    expect(repository.tasks.single.name, 'Review');
  });

  test('deletes a task from memory and storage', () async {
    await viewModel.startTask('Planning');
    await viewModel.deleteTask(viewModel.runningTasks.single);

    expect(viewModel.tasks, isEmpty);
    expect(repository.tasks, isEmpty);
  });
}

class _MemoryTaskRepository implements TaskRepository {
  final List<Task> tasks = [];
  final Map<String, int> colors = {};

  @override
  Future<TaskData> load() async => (tasks: [...tasks], colors: {...colors});

  @override
  Future<void> saveTask(Task task, {String? colorKey, int? colorValue}) async {
    tasks.removeWhere((item) => item.id == task.id);
    tasks.add(task);
    if (colorKey != null && colorValue != null) colors[colorKey] = colorValue;
  }

  @override
  Future<void> deleteTask(String id) async =>
      tasks.removeWhere((task) => task.id == id);
}
