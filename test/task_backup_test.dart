import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/domain/task_backup.dart';

Future<String> _encode(List<BackupEntry> entries) async =>
    (await encodeBackup(Stream.fromIterable(entries)).toList()).join();

Future<List<BackupEntry>> _decode(Stream<String> text) =>
    decodeBackup(text).toList();

void main() {
  test('round-trips the header, tasks, and both kinds of color', () async {
    final startedAt = DateTime.utc(2026, 10, 29, 9, 30);
    final exportedAt = DateTime.utc(2026, 10, 29);
    final task = Task(
      id: 'task-1',
      name: 'Planning',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(hours: 1)),
      notes: 'Roadmap\nFollow-ups',
    );

    final csv = await _encode([
      BackupHeader(exportedAt),
      BackupTaskEntry(task),
      const BackupColorEntry('planning', 0xFF123456),
      const BackupCustomColorEntry(0xFFABCDEF),
    ]);
    final decoded = await _decode(Stream.value(csv));

    expect((decoded[0] as BackupHeader).exportedAt, exportedAt);
    expect((decoded[1] as BackupTaskEntry).task.notes, 'Roadmap\nFollow-ups');
    expect((decoded[1] as BackupTaskEntry).task.endedAt, task.endedAt);
    expect((decoded[2] as BackupColorEntry).key, 'planning');
    expect((decoded[2] as BackupColorEntry).argb, 0xFF123456);
    expect((decoded[3] as BackupCustomColorEntry).argb, 0xFFABCDEF);
  });

  test(
    'starts with a single #kronos-backup line and omits per-row types',
    () async {
      final csv = await _encode([
        BackupHeader(DateTime.utc(2026)),
        BackupTaskEntry(
          Task(id: 'task-1', name: 'Planning', startedAt: DateTime.utc(2026)),
        ),
      ]);

      final lines = csv.split('\r\n');
      expect(
        lines.first,
        startsWith('#kronos-backup,1,2026-01-01T00:00:00.000Z'),
      );
      expect(lines[1], '#tasks,id,name,started_at,ended_at,notes');
      expect(lines[2], startsWith('task-1,Planning,'));
      expect(csv, isNot(contains('meta')));
    },
  );

  test('preserves delimiters, quotes, and number-like names exactly', () async {
    final startedAt = DateTime.utc(2026, 1, 1);
    final names = ['Write; review | "draft", 1e5', '007', 'true'];
    final csv = await _encode([
      BackupHeader(DateTime.utc(2026)),
      for (final (index, name) in names.indexed)
        BackupTaskEntry(
          Task(
            id: 'task-$index',
            name: name,
            startedAt: startedAt.add(Duration(minutes: index)),
            notes: 'Notes, with "quotes"\nand a newline',
          ),
        ),
    ]);

    final tasks = (await _decode(
      Stream.value(csv),
    )).whereType<BackupTaskEntry>().map((entry) => entry.task).toList();

    expect(tasks.map((task) => task.name), names);
    expect(tasks.first.notes, 'Notes, with "quotes"\nand a newline');
    expect(tasks.first.endedAt, isNull);
  });

  test('decodes the same backup when split into tiny chunks', () async {
    final csv = await _encode([
      BackupHeader(DateTime.utc(2026)),
      BackupTaskEntry(
        Task(
          id: 'task-1',
          name: 'Split, "across"\nlines',
          startedAt: DateTime.utc(2026),
          notes: 'x',
        ),
      ),
      const BackupCustomColorEntry(0xFF000000),
    ]);
    final chunks = [
      for (var i = 0; i < csv.length; i += 3)
        csv.substring(i, i + 3 > csv.length ? csv.length : i + 3),
    ];

    final decoded = await _decode(Stream.fromIterable(chunks));

    expect((decoded[1] as BackupTaskEntry).task.name, 'Split, "across"\nlines');
    expect((decoded[2] as BackupCustomColorEntry).argb, 0xFF000000);
  });

  test('rejects a file that is not a Kronos backup', () async {
    await expectLater(
      _decode(Stream.value('{"format":"kronos-backup"}')),
      throwsFormatException,
    );
    await expectLater(_decode(Stream.value('')), throwsFormatException);
  });

  test('rejects an unsupported version', () async {
    await expectLater(
      _decode(Stream.value('#kronos-backup,2,2026-01-01T00:00:00.000Z\r\n')),
      throwsFormatException,
    );
  });

  test('rejects a task that ends before it starts', () async {
    final startedAt = DateTime.utc(2026, 1, 2);
    final csv = await _encode([
      BackupHeader(DateTime.utc(2026)),
      BackupTaskEntry(
        Task(
          id: 'invalid',
          name: 'Invalid',
          startedAt: startedAt,
          endedAt: startedAt.subtract(const Duration(hours: 1)),
        ),
      ),
    ]);

    await expectLater(_decode(Stream.value(csv)), throwsFormatException);
  });

  test(
    'rejects rows outside a section and unexpected section layouts',
    () async {
      const outside =
          '#kronos-backup,1,2026-01-01T00:00:00.000Z\r\nstray,row\r\n';
      await expectLater(_decode(Stream.value(outside)), throwsFormatException);

      const layout =
          '#kronos-backup,1,2026-01-01T00:00:00.000Z\r\n'
          '#tasks,id,name\r\n';
      await expectLater(_decode(Stream.value(layout)), throwsFormatException);
    },
  );

  test('ignores comment lines that are not directives', () async {
    const csv =
        '#kronos-backup,1,2026-01-01T00:00:00.000Z\r\n'
        '# exported by hand\r\n'
        '#custom_colors,argb\r\n'
        '4278190080\r\n';

    final decoded = await _decode(Stream.value(csv));

    expect(decoded, hasLength(2));
    expect((decoded[1] as BackupCustomColorEntry).argb, 4278190080);
  });
}
