import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/data/backup_service.dart';
import 'package:kronos/data/task_repository.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/domain/task_backup.dart';
import 'package:kronos/domain/task_filter.dart';
import 'package:kronos/presentation/duration_bar_chart.dart';
import 'package:kronos/presentation/kronos_app.dart';
import 'package:kronos/presentation/task_view_model.dart';

void main() {
  testWidgets('starts a task and moves it to completed when stopped', (
    tester,
  ) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    await tester.pumpWidget(KronosApp(viewModel: viewModel));
    await tester.pump();
    await tester.pump();

    expect(find.text('No completed tasks yet'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Write report');
    await tester.pump();
    await tester.tap(find.byTooltip('Start task'));
    await tester.pump();
    await tester.pump();

    expect(viewModel.runningTasks, hasLength(1));
    expect(find.text('Write report'), findsOneWidget);
    expect(find.text('IN PROGRESS'), findsNothing);
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.text('Write report'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings can select and persist the dark theme', (tester) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    await tester.pumpWidget(KronosApp(viewModel: viewModel));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.text('Dark')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.secondary, const Color(0xFF05F2DB));
    expect(theme.colorScheme.surface, const Color(0xFF302E32));
    expect(theme.colorScheme.surfaceContainerHighest, const Color(0xFF454247));
    expect(repository.themeMode, 'dark');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings display backup and restore controls', (tester) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    final backupService = BackupService(repository);
    await tester.pumpWidget(
      KronosApp(viewModel: viewModel, backupService: backupService),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('DATA & BACKUP'), findsOneWidget);
    expect(find.text('Automatic backups'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('task color picker defaults to the selectable no-color option', (
    tester,
  ) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    await viewModel.startTask('Planning');
    await tester.pumpWidget(KronosApp(viewModel: viewModel));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Planning'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('No color'), findsOneWidget);
    expect(find.byKey(const Key('no-color-cross')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('no-color-cross')),
        matching: find.byType(ClipOval),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('task edit opens date, hour, and minute wheels together', (
    tester,
  ) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    await viewModel.startTask('Planning');
    await tester.pumpWidget(KronosApp(viewModel: viewModel));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Planning'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Started'));
    await tester.pumpAndSettle();

    expect(find.byType(ListWheelScrollView), findsNWidgets(3));
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('separates running tasks with a divider but no heading', (
    tester,
  ) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    await viewModel.startTask('Planning');
    await viewModel.startTask('Review');
    await tester.pumpWidget(KronosApp(viewModel: viewModel));
    await tester.pump();
    await tester.pump();

    expect(find.text('IN PROGRESS'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.height, 1);
    expect(divider.thickness, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'autocomplete overlays the input without shifting running tasks',
    (tester) async {
      final repository = _MemoryTaskRepository();
      final viewModel = TaskViewModel(repository);
      await viewModel.startTask('Planning');
      await viewModel.startTask('Review');
      await tester.pumpWidget(KronosApp(viewModel: viewModel));
      await tester.pump();
      await tester.pump();

      final runningTaskStop = find.byTooltip('Stop Planning');
      final topBeforeSuggestions = tester.getTopLeft(runningTaskStop).dy;
      await tester.enterText(find.byType(TextField), 'Plan');
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
      expect(find.text('Planning'), findsNWidgets(2));
      expect(tester.getTopLeft(runningTaskStop).dy, topBeforeSuggestions);
      final suggestionTop = tester
          .getTopLeft(find.byIcon(Icons.history_rounded))
          .dy;
      final inputTop = tester.getTopLeft(find.byType(TextField)).dy;
      expect(suggestionTop, greaterThanOrEqualTo(0));
      expect(suggestionTop, lessThan(inputTop));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('search filters completed tasks by name', (tester) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    await viewModel.startTask('Write report');
    await viewModel.stopTask(viewModel.runningTasks.single);
    await viewModel.startTask('Review notes');
    await viewModel.stopTask(viewModel.runningTasks.single);
    await tester.pumpWidget(KronosApp(viewModel: viewModel));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Search and filter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'WRITE');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Write report'), findsOneWidget);
    expect(find.text('Review notes'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('analytics compares durations and time between instances', (
    tester,
  ) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    final now = DateTime.now();
    repository._tasks.addAll([
      Task(
        id: 'planning-1',
        name: 'Planning',
        startedAt: now.subtract(const Duration(hours: 3)),
        endedAt: now.subtract(const Duration(hours: 2)),
      ),
      Task(
        id: 'planning-2',
        name: 'Planning',
        startedAt: now.subtract(const Duration(hours: 1)),
        endedAt: now.subtract(const Duration(minutes: 30)),
      ),
    ]);
    await tester.pumpWidget(KronosApp(viewModel: viewModel));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('2 samples'), findsOneWidget);
    expect(find.byType(DurationBarChart), findsOneWidget);

    await tester.tap(find.text('Time between instances'));
    await tester.pumpAndSettle();
    expect(find.text('1 sample'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saves multiline notes from task details', (tester) async {
    final repository = _MemoryTaskRepository();
    final viewModel = TaskViewModel(repository);
    await viewModel.startTask('Planning');
    await tester.pumpWidget(KronosApp(viewModel: viewModel));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Planning'));
    await tester.pumpAndSettle();
    expect(find.text('Task details'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('NOTES'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('task-notes')),
      'First line\nSecond line',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(viewModel.runningTasks.single.notes, 'First line\nSecond line');
    expect(repository._tasks.single.notes, 'First line\nSecond line');
    await tester.pumpWidget(const SizedBox());
  });
}

class _MemoryTaskRepository implements TaskRepository {
  final List<Task> _tasks = [];
  final Map<String, int> _colors = {};
  final List<int> _customColors = [];
  final Map<String, String> _settings = {};
  String? themeMode;

  @override
  Future<InitialTaskData> loadInitial({
    required int pageSize,
    TaskFilter filter = const TaskFilter(),
  }) async {
    final running = _tasks.where((task) => task.isRunning).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final completed =
        _tasks
            .where((task) => !task.isRunning && _matches(task, filter))
            .toList()
          ..sort((a, b) {
            final byDate = b.startedAt.compareTo(a.startedAt);
            return byDate != 0 ? byDate : b.id.compareTo(a.id);
          });
    return InitialTaskData(
      runningTasks: running,
      completedPage: _page(completed, pageSize),
      taskNames: await loadTaskNames(),
      colors: {..._colors},
      customColors: [..._customColors],
    );
  }

  @override
  Future<TaskPage> loadCompletedPage({
    required int pageSize,
    TaskFilter filter = const TaskFilter(),
    TaskCursor? before,
  }) async {
    final completed =
        _tasks
            .where((task) => !task.isRunning && _matches(task, filter))
            .toList()
          ..sort((a, b) {
            final byDate = b.startedAt.compareTo(a.startedAt);
            return byDate != 0 ? byDate : b.id.compareTo(a.id);
          });
    final remaining = before == null
        ? completed
        : completed.where((task) {
            final dateCompare = task.startedAt.compareTo(before.startedAt);
            return dateCompare < 0 ||
                (dateCompare == 0 && task.id.compareTo(before.id) < 0);
          }).toList();
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
      _tasks.map((task) => task.name).toSet().toList();

  @override
  Future<String?> loadThemeMode() async => themeMode;

  @override
  Future<void> saveThemeMode(String mode) async => themeMode = mode;

  @override
  Future<String?> loadSetting(String key) async => _settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    _settings[key] = value;
  }

  @override
  Future<void> deleteSetting(String key) async => _settings.remove(key);

  @override
  Future<List<int>> loadCustomColors() async => [..._customColors];

  @override
  Future<void> addCustomColor(int argb) async {
    if (!_customColors.contains(argb)) _customColors.add(argb);
  }

  @override
  Future<TaskBackup> exportBackup() async => TaskBackup(
    exportedAt: DateTime.now(),
    tasks: [..._tasks],
    colors: {..._colors},
    customColors: [..._customColors],
  );

  @override
  Future<void> restoreBackup(TaskBackup backup) async {
    _tasks
      ..clear()
      ..addAll(backup.tasks);
    _colors
      ..clear()
      ..addAll(backup.colors);
    _customColors
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
    _tasks.removeWhere((item) => item.id == task.id);
    _tasks.add(task);
    if (colorKey != null && colorValue != null) _colors[colorKey] = colorValue;
    if (clearColor && colorKey != null) _colors.remove(colorKey);
  }

  @override
  Future<void> deleteTask(String id) async =>
      _tasks.removeWhere((task) => task.id == id);

  @override
  Stream<Task> streamTasksNamed(String name, {DateTime? startedBefore}) async* {
    final matching =
        _tasks.where((task) {
          return task.name.toLowerCase() == name.toLowerCase() &&
              (startedBefore == null || !task.startedAt.isAfter(startedBefore));
        }).toList()..sort((a, b) {
          final byStart = a.startedAt.compareTo(b.startedAt);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
    yield* Stream.fromIterable(matching);
  }
}
