import 'dart:async';

import 'package:flutter/material.dart';

import '../data/task_repository.dart';
import '../domain/task.dart';

class TaskViewModel extends ChangeNotifier {
  TaskViewModel(this._repository) {
    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
  }

  final TaskRepository _repository;
  late final Timer _clock;
  List<Task> _tasks = [];
  Map<String, int> _colors = {};
  bool _isLoaded = false;

  List<Task> get tasks => List.unmodifiable(_tasks);
  bool get isLoaded => _isLoaded;
  DateTime get now => DateTime.now();

  List<Task> get runningTasks =>
      _tasks.where((task) => task.isRunning).toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  List<Task> get completedTasks =>
      _tasks.where((task) => !task.isRunning).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  List<String> suggestionsFor(String input) {
    final query = input.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final names = _tasks.map((task) => task.name).toSet();
    return names.where((name) => name.toLowerCase().contains(query)).toList()
      ..sort((a, b) {
        final aPrefix = a.toLowerCase().startsWith(query);
        final bPrefix = b.toLowerCase().startsWith(query);
        if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
  }

  Color colorFor(String name) {
    final stored = _colors[taskColorKey(name)];
    if (stored != null) return Color(stored);
    final index = taskColorKey(name).hashCode.abs() % taskColors.length;
    return taskColors[index];
  }

  Future<void> load() async {
    final data = await _repository.load();
    _tasks = data.tasks;
    _colors = data.colors;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> startTask(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final existingName = _tasks
        .map((task) => task.name)
        .where((taskName) => taskName.toLowerCase() == cleanName.toLowerCase())
        .firstOrNull;
    final task = Task(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: existingName ?? cleanName,
      startedAt: DateTime.now(),
    );
    _tasks = [..._tasks, task];
    await _persistTask(task);
  }

  Future<void> stopTask(Task task) async {
    final stopped = task.copyWith(endedAt: DateTime.now());
    _replace(stopped);
    await _persistTask(stopped);
  }

  Future<void> deleteTask(Task task) async {
    _tasks = _tasks.where((item) => item.id != task.id).toList();
    notifyListeners();
    await _repository.deleteTask(task.id);
  }

  Future<void> updateTask(Task updated, {Color? color}) async {
    if (updated.name.trim().isEmpty) return;
    final old = _tasks.firstWhere((task) => task.id == updated.id);
    final name = updated.name.trim();
    final savedTask = updated.copyWith(name: name);
    _replace(savedTask);
    final int? colorValue =
        color?.toARGB32() ?? _colors[taskColorKey(old.name)];
    if (colorValue != null) {
      _colors[taskColorKey(name)] = colorValue;
    }
    notifyListeners();
    await _repository.saveTask(
      savedTask,
      colorKey: colorValue == null ? null : taskColorKey(name),
      colorValue: colorValue,
    );
  }

  void _replace(Task replacement) {
    _tasks = _tasks
        .map((task) => task.id == replacement.id ? replacement : task)
        .toList();
    notifyListeners();
  }

  Future<void> _persistTask(Task task) async {
    notifyListeners();
    final color = _colors[taskColorKey(task.name)];
    await _repository.saveTask(
      task,
      colorKey: color == null ? null : taskColorKey(task.name),
      colorValue: color,
    );
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
