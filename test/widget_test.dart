import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/data/task_repository.dart';
import 'package:kronos/domain/task.dart';
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
  String? themeMode;

  @override
  Future<InitialTaskData> loadInitial({required int pageSize}) async {
    final running = _tasks.where((task) => task.isRunning).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final completed = _tasks.where((task) => !task.isRunning).toList()
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
    TaskCursor? before,
  }) async {
    final completed = _tasks.where((task) => !task.isRunning).toList()
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
  Future<List<int>> loadCustomColors() async => [..._customColors];

  @override
  Future<void> addCustomColor(int argb) async {
    if (!_customColors.contains(argb)) _customColors.add(argb);
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
}
