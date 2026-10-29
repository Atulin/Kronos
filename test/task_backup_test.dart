import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/domain/task_backup.dart';

void main() {
  test('round-trips task details, colors, and custom swatches', () {
    final startedAt = DateTime.utc(2026, 10, 29, 9, 30);
    final backup = TaskBackup(
      exportedAt: DateTime.utc(2026, 10, 29),
      tasks: [
        Task(
          id: 'task-1',
          name: 'Planning',
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(hours: 1)),
          notes: 'Roadmap\nFollow-ups',
        ),
      ],
      colors: {'planning': 0xFF123456},
      customColors: [0xFFABCDEF],
    );

    final decoded = TaskBackup.fromJson(
      jsonDecode(jsonEncode(backup.toJson())),
    );

    expect(decoded.exportedAt, backup.exportedAt);
    expect(decoded.tasks.single.notes, 'Roadmap\nFollow-ups');
    expect(
      decoded.tasks.single.endedAt,
      startedAt.add(const Duration(hours: 1)),
    );
    expect(decoded.colors['planning'], 0xFF123456);
    expect(decoded.customColors, [0xFFABCDEF]);
  });

  test(
    'rejects a backup with an unsupported version or invalid task range',
    () {
      final json = {
        'format': TaskBackup.format,
        'version': TaskBackup.currentVersion + 1,
        'exportedAt': DateTime.utc(2026).toIso8601String(),
        'tasks': <Object?>[],
        'colors': <String, int>{},
        'customColors': <int>[],
      };
      expect(() => TaskBackup.fromJson(json), throwsFormatException);

      json['version'] = TaskBackup.currentVersion;
      json['tasks'] = [
        {
          'id': 'invalid',
          'name': 'Invalid',
          'startedAt': DateTime.utc(2026, 1, 2).toIso8601String(),
          'endedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        },
      ];
      expect(() => TaskBackup.fromJson(json), throwsFormatException);
    },
  );
}
