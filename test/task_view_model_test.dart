import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/data/notification_service.dart';
import 'package:kronos/data/task_repository.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/domain/task_backup.dart';
import 'package:kronos/domain/task_filter.dart';
import 'package:kronos/domain/task_reminder.dart';
import 'package:kronos/presentation/task_view_model.dart';

class _FakeReminderNotifier implements ReminderNotifier {
  final List<String> events = [];
  int requestedPermissions = 0;
  int resyncs = 0;

  @override
  Future<void> scheduleRunningTask(Task task, TaskReminder reminder) async {
    events.add('${task.isRunning ? "start" : "cancel"} ${task.id}');
  }

  @override
  Future<void> cancelRunningTask(Task task) async {
    events.add('cancel ${task.id}');
  }

  @override
  Future<void> cancelAllPending() async {
    resyncs++;
  }

  @override
  Future<void> requestPermissions() async {
    requestedPermissions++;
  }

  @override
  Future<void> showPreview(TaskReminder reminder) async {
    events.add('preview ${reminder.sound}');
  }
}

void main() {
  late _MemoryTaskRepository repository;
  late _FakeReminderNotifier notifier;
  late TaskViewModel viewModel;

  setUp(() async {
    repository = _MemoryTaskRepository();
    notifier = _FakeReminderNotifier();
    viewModel = TaskViewModel(repository, notifier: notifier);
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

  test('saves one reminder per task name and re-arms running tasks', () async {
    await viewModel.startTask('On a break');
    final task = viewModel.runningTasks.single;
    notifier.events.clear();

    const reminder = TaskReminder(interval: Duration(minutes: 30));
    await viewModel.setReminder('ON A BREAK', reminder);

    expect(viewModel.reminderFor('On a break'), reminder);
    expect(repository.reminders['on a break'], reminder);
    expect(notifier.events, ['start ${task.id}']);
    expect(notifier.requestedPermissions, 1);

    notifier.events.clear();
    await viewModel.setReminder('On a break', null);

    expect(viewModel.reminderFor('on a break'), isNull);
    expect(repository.reminders.containsKey('on a break'), isFalse);
    expect(notifier.events, ['cancel ${task.id}']);
    expect(notifier.requestedPermissions, 1);
  });

  test(
    'starts arm reminders by name; stopping and deleting disarm them',
    () async {
      repository.reminders['baking'] = const TaskReminder(
        interval: Duration(minutes: 15),
        repeats: true,
      );
      await viewModel.load();

      await viewModel.startTask('Baking');
      final task = viewModel.runningTasks.single;
      expect(notifier.events, ['start ${task.id}']);

      notifier.events.clear();
      await viewModel.stopTask(task);
      expect(notifier.events, ['cancel ${task.id}']);

      await viewModel.startTask('Baking');
      final restarted = viewModel.runningTasks.single;
      notifier.events.clear();
      await viewModel.deleteTask(restarted);
      expect(notifier.events, ['cancel ${restarted.id}']);
      expect(repository.reminders, containsPair('baking', isNotNull));
    },
  );

  test('renaming a task moves its schedule to the new name', () async {
    await viewModel.startTask('Planning');
    final task = viewModel.runningTasks.single;
    await viewModel.setReminder(
      'planning',
      const TaskReminder(interval: Duration(minutes: 5)),
    );
    notifier.events.clear();

    await viewModel.updateTask(task.copyWith(name: 'Focus'), color: null);

    // No reminder for 'Focus', so the schedule is dropped.
    expect(notifier.events, ['cancel ${task.id}']);

    await viewModel.setReminder(
      'focus',
      const TaskReminder(interval: Duration(minutes: 45)),
    );
    expect(notifier.events, ['cancel ${task.id}', 'start ${task.id}']);
  });

  test('reloading re-arms reminders for currently running tasks', () async {
    await viewModel.startTask('On a break');
    repository.reminders['on a break'] = const TaskReminder(
      interval: Duration(minutes: 30),
    );
    notifier.events.clear();
    notifier.resyncs = 0;

    await viewModel.load();

    expect(notifier.resyncs, 1);
    expect(notifier.events, ['start ${viewModel.runningTasks.single.id}']);
  });

  test('previews use the configured reminder sound', () async {
    const reminder = TaskReminder(
      interval: Duration(minutes: 10),
      repeats: true,
      sound: 'chime',
    );
    await viewModel.showReminderPreview(reminder);

    expect(notifier.events, ['preview chime']);
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
  final Map<String, TaskReminder> reminders = {};
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
      reminders: {...reminders},
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
  Future<void> saveReminder(String nameKey, TaskReminder reminder) async {
    reminders[nameKey] = reminder;
  }

  @override
  Future<void> deleteReminder(String nameKey) async {
    reminders.remove(nameKey);
  }

  @override
  Stream<BackupEntry> exportBackupEntries() async* {
    yield BackupHeader(DateTime.now());
    for (final task in tasks) {
      yield BackupTaskEntry(task);
    }
    for (final entry in colors.entries) {
      yield BackupColorEntry(entry.key, entry.value);
    }
    for (final argb in customColors) {
      yield BackupCustomColorEntry(argb);
    }
    for (final entry in reminders.entries) {
      yield BackupReminderEntry(entry.key, entry.value);
    }
  }

  @override
  Future<void> restoreBackup(Stream<BackupEntry> entries) async {
    final restored = await entries.toList();
    tasks
      ..clear()
      ..addAll(
        restored.whereType<BackupTaskEntry>().map((entry) => entry.task),
      );
    colors
      ..clear()
      ..addEntries(
        restored.whereType<BackupColorEntry>().map(
          (entry) => MapEntry(entry.key, entry.argb),
        ),
      );
    customColors
      ..clear()
      ..addAll(restored.whereType<BackupCustomColorEntry>().map((e) => e.argb));
    reminders
      ..clear()
      ..addEntries(
        restored.whereType<BackupReminderEntry>().map(
          (entry) => MapEntry(entry.key, entry.reminder),
        ),
      );
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
