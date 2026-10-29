import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/data/task_repository.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/domain/task_backup.dart';
import 'package:kronos/domain/task_filter.dart';
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

    expect(viewModel.runningTasks, isEmpty);
    expect(viewModel.completedTasks, isEmpty);
    expect(repository.tasks, isEmpty);
  });

  test('loads completed tasks in cursor-paginated batches', () async {
    final pagedRepository = _MemoryTaskRepository();
    final firstDate = DateTime.utc(2024);
    for (var index = 0; index < 100; index++) {
      final startedAt = firstDate.add(Duration(minutes: index));
      pagedRepository.tasks.add(
        Task(
          id: 'task-$index',
          name: 'Task $index',
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(minutes: 1)),
        ),
      );
    }
    final pagedViewModel = TaskViewModel(pagedRepository);
    addTearDown(pagedViewModel.dispose);

    await pagedViewModel.load();
    expect(pagedViewModel.completedTasks, hasLength(TaskViewModel.pageSize));
    expect(pagedViewModel.hasMoreCompleted, isTrue);
    await pagedViewModel.loadMoreCompleted();
    expect(pagedViewModel.completedTasks, hasLength(100));
    expect(pagedViewModel.hasMoreCompleted, isFalse);
  });

  test('no color clears the shared color for a task name', () async {
    await viewModel.startTask('Planning');
    var task = viewModel.runningTasks.single;
    await viewModel.updateTask(
      task.copyWith(name: 'Planning'),
      color: const Color(0xFF123456),
    );
    task = viewModel.runningTasks.single;

    await viewModel.updateTask(task, color: null);

    expect(viewModel.colorFor('Planning'), isNull);
    expect(repository.colors.containsKey('planning'), isFalse);
  });

  test('persists the selected appearance mode', () async {
    await viewModel.setThemeMode(ThemeMode.dark);
    final restarted = TaskViewModel(repository);
    addTearDown(restarted.dispose);

    await restarted.load();

    expect(restarted.themeMode, ThemeMode.dark);
  });

  test('applies completed-task filters without hiding running tasks', () async {
    await viewModel.startTask('Write report');
    await viewModel.stopTask(viewModel.runningTasks.single);
    await viewModel.startTask('Review');
    await viewModel.stopTask(viewModel.runningTasks.single);
    await viewModel.startTask('Current task');

    await viewModel.applyFilter(const TaskFilter(query: 'write'));

    expect(viewModel.completedTasks, hasLength(1));
    expect(viewModel.completedTasks.single.name, 'Write report');
    expect(viewModel.runningTasks.single.name, 'Current task');
    expect(viewModel.filter.isActive, isTrue);
    expect(viewModel.hasMoreCompleted, isFalse);
  });

  test('persists custom swatches and task notes', () async {
    const color = Color(0xFF12ABCD);
    await viewModel.addCustomColor(color);
    await viewModel.addCustomColor(color);
    await viewModel.startTask('Planning');
    final task = viewModel.runningTasks.single;
    await viewModel.updateTask(
      task.copyWith(notes: 'First line\nSecond line'),
      color: color,
    );

    final restarted = TaskViewModel(repository);
    addTearDown(restarted.dispose);
    await restarted.load();

    expect(restarted.customColors, [color]);
    expect(restarted.runningTasks.single.notes, 'First line\nSecond line');
  });
}

class _MemoryTaskRepository implements TaskRepository {
  final List<Task> tasks = [];
  final Map<String, int> colors = {};
  final List<int> customColors = [];
  final Map<String, String> settings = {};
  String? themeMode;

  @override
  Future<InitialTaskData> loadInitial({
    required int pageSize,
    TaskFilter filter = const TaskFilter(),
  }) async {
    final running = tasks.where((task) => task.isRunning).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final completed =
        tasks
            .where((task) => !task.isRunning && _matches(task, filter))
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return InitialTaskData(
      runningTasks: running,
      completedPage: _page(completed, pageSize),
      taskNames: await loadTaskNames(),
      colors: {...colors},
      customColors: [...customColors],
    );
  }

  @override
  Future<TaskPage> loadCompletedPage({
    required int pageSize,
    TaskFilter filter = const TaskFilter(),
    TaskCursor? before,
  }) async {
    final completed =
        tasks
            .where((task) => !task.isRunning && _matches(task, filter))
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final remaining = before == null
        ? completed
        : completed
              .where((task) => task.startedAt.isBefore(before.startedAt))
              .toList();
    return _page(remaining, pageSize);
  }

  bool _matches(Task task, TaskFilter filter) {
    final query = filter.query.trim().toLowerCase();
    return (query.isEmpty || task.name.toLowerCase().contains(query)) &&
        (filter.startedAfter == null ||
            !task.startedAt.isBefore(filter.startedAfter!)) &&
        (filter.startedBefore == null ||
            !task.startedAt.isAfter(filter.startedBefore!));
  }

  TaskPage _page(List<Task> tasks, int pageSize) {
    final hasMore = tasks.length > pageSize;
    final page = hasMore ? tasks.take(pageSize).toList() : tasks;
    final last = page.isEmpty ? null : page.last;
    return TaskPage(
      tasks: page,
      hasMore: hasMore,
      nextCursor: hasMore && last != null
          ? TaskCursor(startedAt: last.startedAt, id: last.id)
          : null,
    );
  }

  @override
  Future<List<String>> loadTaskNames() async =>
      tasks.map((task) => task.name).toSet().toList();

  @override
  Future<String?> loadThemeMode() async => themeMode;

  @override
  Future<void> saveThemeMode(String mode) async => themeMode = mode;

  @override
  Future<String?> loadSetting(String key) async => settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    settings[key] = value;
  }

  @override
  Future<void> deleteSetting(String key) async => settings.remove(key);

  @override
  Future<List<int>> loadCustomColors() async => [...customColors];

  @override
  Future<void> addCustomColor(int argb) async {
    if (!customColors.contains(argb)) customColors.add(argb);
  }

  @override
  Future<TaskBackup> exportBackup() async => TaskBackup(
    exportedAt: DateTime.now(),
    tasks: [...tasks],
    colors: {...colors},
    customColors: [...customColors],
  );

  @override
  Future<void> restoreBackup(TaskBackup backup) async {
    tasks
      ..clear()
      ..addAll(backup.tasks);
    colors
      ..clear()
      ..addAll(backup.colors);
    customColors
      ..clear()
      ..addAll(backup.customColors);
  }

  @override
  Future<void> saveTask(
    Task task, {
    String? colorKey,
    int? colorValue,
    bool clearColor = false,
  }) async {
    tasks.removeWhere((item) => item.id == task.id);
    tasks.add(task);
    if (colorKey != null && colorValue != null) colors[colorKey] = colorValue;
    if (clearColor && colorKey != null) colors.remove(colorKey);
  }

  @override
  Future<void> deleteTask(String id) async =>
      tasks.removeWhere((task) => task.id == id);

  @override
  Stream<Task> streamTasksNamed(String name, {DateTime? startedBefore}) async* {
    final matching =
        tasks.where((task) {
          return task.name.toLowerCase() == name.toLowerCase() &&
              (startedBefore == null || !task.startedAt.isAfter(startedBefore));
        }).toList()..sort((a, b) {
          final byStart = a.startedAt.compareTo(b.startedAt);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
    yield* Stream.fromIterable(matching);
  }
}
