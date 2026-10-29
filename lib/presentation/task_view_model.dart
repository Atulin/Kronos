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

  static const pageSize = 75;

  final TaskRepository _repository;
  late final Timer _clock;
  List<Task> _runningTasks = [];
  List<Task> _completedTasks = [];
  List<String> _taskNames = [];
  Map<String, int> _colors = {};
  List<int> _customColors = [];
  TaskCursor? _completedCursor;
  ThemeMode _themeMode = ThemeMode.system;
  bool _hasMoreCompleted = false;
  bool _isLoadingMore = false;
  bool _isLoaded = false;

  List<Task> get runningTasks => List.unmodifiable(_runningTasks);
  List<Task> get completedTasks => List.unmodifiable(_completedTasks);
  bool get isLoaded => _isLoaded;
  bool get hasMoreCompleted => _hasMoreCompleted;
  bool get isLoadingMore => _isLoadingMore;
  ThemeMode get themeMode => _themeMode;
  List<Color> get customColors =>
      _customColors.map((argb) => Color(argb)).toList(growable: false);
  DateTime get now => DateTime.now();

  List<String> suggestionsFor(String input) {
    final query = input.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _taskNames
        .where((name) => name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) {
        final aPrefix = a.toLowerCase().startsWith(query);
        final bPrefix = b.toLowerCase().startsWith(query);
        if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
  }

  Color? colorFor(String name) {
    final stored = _colors[taskColorKey(name)];
    return stored == null ? null : Color(stored);
  }

  Future<void> load() async {
    final data = await _repository.loadInitial(pageSize: pageSize);
    final savedThemeMode = await _repository.loadThemeMode();
    _runningTasks = data.runningTasks;
    _completedTasks = data.completedPage.tasks;
    _completedCursor = data.completedPage.nextCursor;
    _hasMoreCompleted = data.completedPage.hasMore;
    _taskNames = data.taskNames;
    _colors = data.colors;
    _customColors = data.customColors;
    _themeMode = _themeModeFromName(savedThemeMode);
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> loadMoreCompleted() async {
    if (!_isLoaded || !_hasMoreCompleted || _isLoadingMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _repository.loadCompletedPage(
        pageSize: pageSize,
        before: _completedCursor,
      );
      final loadedIds = _completedTasks.map((task) => task.id).toSet();
      _completedTasks = [
        ..._completedTasks,
        ...page.tasks.where((task) => loadedIds.add(task.id)),
      ];
      _completedCursor = page.nextCursor;
      _hasMoreCompleted = page.hasMore;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _repository.saveThemeMode(mode.name);
  }

  Future<void> addCustomColor(Color color) async {
    final argb = color.toARGB32();
    if (taskColors.any((swatch) => swatch.toARGB32() == argb) ||
        _customColors.contains(argb)) {
      return;
    }
    _customColors = [..._customColors, argb];
    notifyListeners();
    await _repository.addCustomColor(argb);
  }

  Future<void> startTask(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final existingName = _taskNames
        .where((taskName) => taskName.toLowerCase() == cleanName.toLowerCase())
        .firstOrNull;
    final task = Task(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: existingName ?? cleanName,
      startedAt: DateTime.now(),
    );
    _runningTasks = [..._runningTasks, task]..sort(_compareRunning);
    if (existingName == null) _taskNames = [..._taskNames, cleanName];
    await _persistTask(task);
  }

  Future<void> stopTask(Task task) async {
    final stopped = task.copyWith(endedAt: DateTime.now());
    _runningTasks = _runningTasks.where((item) => item.id != task.id).toList();
    _insertCompleted(stopped);
    await _persistTask(stopped);
  }

  Future<void> deleteTask(Task task) async {
    _runningTasks = _runningTasks.where((item) => item.id != task.id).toList();
    _completedTasks = _completedTasks
        .where((item) => item.id != task.id)
        .toList();
    notifyListeners();
    await _repository.deleteTask(task.id);
    _taskNames = await _repository.loadTaskNames();
    notifyListeners();
  }

  Future<void> updateTask(Task updated, {required Color? color}) async {
    if (updated.name.trim().isEmpty) return;
    final savedTask = updated.copyWith(name: updated.name.trim());
    _runningTasks = _runningTasks
        .where((task) => task.id != savedTask.id)
        .toList();
    _completedTasks = _completedTasks
        .where((task) => task.id != savedTask.id)
        .toList();
    if (savedTask.isRunning) {
      _runningTasks = [..._runningTasks, savedTask]..sort(_compareRunning);
    } else {
      _insertCompleted(savedTask);
    }

    final colorKey = taskColorKey(savedTask.name);
    if (color == null) {
      _colors.remove(colorKey);
    } else {
      _colors[colorKey] = color.toARGB32();
    }
    notifyListeners();
    await _repository.saveTask(
      savedTask,
      colorKey: colorKey,
      colorValue: color?.toARGB32(),
      clearColor: color == null,
    );
    _taskNames = await _repository.loadTaskNames();
    notifyListeners();
  }

  void _insertCompleted(Task task) {
    _completedTasks = [..._completedTasks, task]..sort(_compareCompleted);
  }

  int _compareRunning(Task a, Task b) {
    final byStart = a.startedAt.compareTo(b.startedAt);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  }

  int _compareCompleted(Task a, Task b) {
    final byStart = b.startedAt.compareTo(a.startedAt);
    return byStart != 0 ? byStart : b.id.compareTo(a.id);
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

  ThemeMode _themeModeFromName(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

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
