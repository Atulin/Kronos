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

    expect(find.text('Start something to get going'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Write report');
    await tester.pump();
    await tester.tap(find.byTooltip('Start task'));
    await tester.pump();
    await tester.pump();

    expect(viewModel.runningTasks, hasLength(1));
    expect(find.text('Write report'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.text('Write report'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _MemoryTaskRepository implements TaskRepository {
  final List<Task> _tasks = [];
  final Map<String, int> _colors = {};

  @override
  Future<TaskData> load() async => (tasks: [..._tasks], colors: {..._colors});

  @override
  Future<void> saveTask(Task task, {String? colorKey, int? colorValue}) async {
    _tasks.removeWhere((item) => item.id == task.id);
    _tasks.add(task);
    if (colorKey != null && colorValue != null) _colors[colorKey] = colorValue;
  }

  @override
  Future<void> deleteTask(String id) async =>
      _tasks.removeWhere((task) => task.id == id);
}
