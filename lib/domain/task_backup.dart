import 'task.dart';

class TaskBackup {
  const TaskBackup({
    required this.exportedAt,
    required this.tasks,
    required this.colors,
    required this.customColors,
  });

  static const format = 'kronos-backup';
  static const currentVersion = 1;

  final DateTime exportedAt;
  final List<Task> tasks;
  final Map<String, int> colors;
  final List<int> customColors;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': currentVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'colors': colors,
    'customColors': customColors,
  };

  factory TaskBackup.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Backup must be a JSON object.');
    }
    final json = Map<String, Object?>.from(value);
    if (json['format'] != format || json['version'] != currentVersion) {
      throw const FormatException(
        'Unsupported Kronos backup format or version.',
      );
    }

    final rawTasks = json['tasks'];
    if (rawTasks is! List) {
      throw const FormatException('Backup tasks must be a JSON array.');
    }
    final tasks = rawTasks.map((rawTask) {
      if (rawTask is! Map) {
        throw const FormatException('Backup contains an invalid task.');
      }
      return Task.fromJson(Map<String, Object?>.from(rawTask));
    }).toList();
    final taskIds = tasks.map((task) => task.id).toSet();
    if (taskIds.length != tasks.length ||
        tasks.any(
          (task) =>
              task.id.isEmpty ||
              task.name.trim().isEmpty ||
              (task.endedAt != null && task.endedAt!.isBefore(task.startedAt)),
        )) {
      throw const FormatException(
        'Backup contains duplicate or invalid tasks.',
      );
    }

    final rawColors = json['colors'];
    if (rawColors is! Map) {
      throw const FormatException('Backup colors must be a JSON object.');
    }
    final colors = <String, int>{};
    for (final entry in rawColors.entries) {
      if (entry.key is! String || entry.value is! int) {
        throw const FormatException('Backup contains an invalid task color.');
      }
      final key = entry.key as String;
      final color = entry.value as int;
      if (key.isEmpty || color < 0 || color > 0xFFFFFFFF) {
        throw const FormatException('Backup contains an invalid task color.');
      }
      colors[key] = color;
    }

    final rawCustomColors = json['customColors'];
    if (rawCustomColors is! List ||
        rawCustomColors.any(
          (color) => color is! int || color < 0 || color > 0xFFFFFFFF,
        )) {
      throw const FormatException('Backup contains invalid custom colors.');
    }
    final customColors = rawCustomColors.cast<int>();
    if (customColors.toSet().length != customColors.length) {
      throw const FormatException('Backup contains duplicate custom colors.');
    }

    final exportedAtValue = json['exportedAt'];
    if (exportedAtValue is! String) {
      throw const FormatException('Backup export timestamp is missing.');
    }
    final exportedAt = DateTime.tryParse(exportedAtValue);
    if (exportedAt == null) {
      throw const FormatException('Backup export timestamp is invalid.');
    }

    return TaskBackup(
      exportedAt: exportedAt,
      tasks: List.unmodifiable(tasks),
      colors: Map.unmodifiable(colors),
      customColors: List.unmodifiable(customColors),
    );
  }
}
