import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/domain/task_backup.dart';

Future<Uint8List> _encode(List<BackupEntry> entries) =>
    encodeBackup(Stream.fromIterable(entries));

Future<List<BackupEntry>> _decode(List<int> bytes) =>
    decodeBackup(Stream.value(bytes)).toList();

Map<String, String> _fileContents(List<int> bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes))
    file.name: utf8.decode(file.content),
};

ArchiveFile _file(String name, String content) =>
    ArchiveFile(name, content.length, utf8.encode(content));

Archive _zipOf(List<ArchiveFile> files) {
  final zip = Archive();
  for (final file in files) {
    zip.addFile(file);
  }
  return zip;
}

const _metadata =
    'format_version,exported_at\r\n2,2026-01-01T00:00:00.000Z\r\n';

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

    final zip = await _encode([
      BackupHeader(exportedAt),
      BackupTaskEntry(task),
      const BackupColorEntry('planning', 0xFF123456),
      const BackupCustomColorEntry(0xFFABCDEF),
    ]);
    final decoded = await _decode(zip);

    expect((decoded[0] as BackupHeader).exportedAt, exportedAt);
    expect((decoded[1] as BackupTaskEntry).task.notes, 'Roadmap\nFollow-ups');
    expect((decoded[1] as BackupTaskEntry).task.endedAt, task.endedAt);
    expect((decoded[2] as BackupColorEntry).key, 'planning');
    expect((decoded[2] as BackupColorEntry).argb, 0xFF123456);
    expect((decoded[3] as BackupCustomColorEntry).argb, 0xFFABCDEF);
  });

  test('writes one spec-compliant CSV per content type', () async {
    final files = _fileContents(
      await _encode([
        BackupHeader(DateTime.utc(2026)),
        BackupTaskEntry(
          Task(id: 'task-1', name: 'Planning', startedAt: DateTime.utc(2026)),
        ),
        const BackupColorEntry('planning', 0xFF123456),
        const BackupCustomColorEntry(0xFFABCDEF),
      ]),
    );

    expect(files.keys, [
      'backup.csv',
      'tasks.csv',
      'task_colors.csv',
      'custom_colors.csv',
    ]);
    expect(files['backup.csv']!.split('\r\n'), [
      'format_version,exported_at',
      '2,2026-01-01T00:00:00.000Z',
      '',
    ]);
    final taskLines = files['tasks.csv']!.split('\r\n');
    expect(taskLines[0], 'id,name,started_at,ended_at,notes');
    expect(taskLines[1], startsWith('task-1,Planning,'));
    expect(files['task_colors.csv']!.split('\r\n'), [
      'name_key,argb',
      'planning,${0xFF123456}',
      '',
    ]);
    expect(files['custom_colors.csv']!.split('\r\n'), [
      'argb',
      '${0xFFABCDEF}',
      '',
    ]);
  });

  test('omits per-row types and #-directives entirely', () async {
    final files = _fileContents(
      await _encode([
        BackupHeader(DateTime.utc(2026)),
        BackupTaskEntry(
          Task(id: 'task-1', name: 'Planning', startedAt: DateTime.utc(2026)),
        ),
        const BackupCustomColorEntry(0xFF000000),
      ]),
    );

    for (final content in files.values) {
      expect(content.split('\r\n'), everyElement(isNot(contains('#'))));
    }
    expect(files['tasks.csv']!.split('\r\n'), [
      'id,name,started_at,ended_at,notes',
      startsWith('task-1,Planning,'),
      '',
    ]);
  });

  test('preserves delimiters, quotes, and number-like names exactly', () async {
    final startedAt = DateTime.utc(2026, 1, 1);
    final names = ['Write; review | "draft", 1e5', '007', 'true'];
    final zip = await _encode([
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

    final tasks = (await _decode(zip)).whereType<BackupTaskEntry>().map(
      (entry) => entry.task,
    ).toList();

    expect(tasks.map((task) => task.name), names);
    expect(tasks.first.notes, 'Notes, with "quotes"\nand a newline');
    expect(tasks.first.endedAt, isNull);
  });

  test('round-trips an empty backup as headers only', () async {
    final decoded = await _decode(
      await _encode([BackupHeader(DateTime.utc(2026))]),
    );

    expect((decoded.single as BackupHeader).exportedAt, DateTime.utc(2026));
  });

  test('decodes the same backup when split into tiny chunks', () async {
    final zip = await _encode([
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
      for (var i = 0; i < zip.length; i += 3)
        Uint8List.sublistView(zip, i, i + 3 > zip.length ? zip.length : i + 3),
    ];

    final decoded = await decodeBackup(Stream.fromIterable(chunks)).toList();

    expect((decoded[1] as BackupTaskEntry).task.name, 'Split, "across"\nlines');
    expect((decoded[2] as BackupCustomColorEntry).argb, 0xFF000000);
  });

  test('rejects bytes that are not a ZIP archive', () async {
    await expectLater(
      _decode(utf8.encode('{"format":"kronos-backup"}')),
      throwsFormatException,
    );
    await expectLater(_decode(const []), throwsFormatException);
  });

  test('rejects a ZIP without Kronos section files', () async {
    final zip = ZipEncoder().encodeBytes(
      _zipOf([_file('something_else.csv', 'id,name\r\n')]),
    );

    await expectLater(_decode(zip), throwsFormatException);
  });

  test('rejects an unsupported version', () async {
    const versionRow = 'format_version,exported_at\r\n'
        '3,2026-01-01T00:00:00.000Z\r\n';
    final zip = ZipEncoder().encodeBytes(
      _zipOf([_file('backup.csv', versionRow)]),
    );

    await expectLater(_decode(zip), throwsFormatException);
  });

  test('rejects a task that ends before it starts', () async {
    final startedAt = DateTime.utc(2026, 1, 2);
    final zip = await _encode([
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

    await expectLater(_decode(zip), throwsFormatException);
  });

  test('rejects unexpected section layouts', () async {
    final wrongColumns = ZipEncoder().encodeBytes(
      _zipOf([
        _file('backup.csv', _metadata),
        _file('tasks.csv', 'id,name\n'),
        _file('task_colors.csv', 'name_key,argb\r\nplanning,427825006\r\n'),
        _file('custom_colors.csv', 'argb\r\n4278190080\r\n'),
      ]),
    );
    final malformedColor = ZipEncoder().encodeBytes(
      _zipOf([
        _file('backup.csv', _metadata),
        _file('tasks.csv', 'id,name,started_at,ended_at,notes\r\n'),
        _file('task_colors.csv', 'name_key,argb\r\nplanning,42782500x6\r\n'),
        _file('custom_colors.csv', 'argb\r\n'),
      ]),
    );

    await expectLater(_decode(wrongColumns), throwsFormatException);
    await expectLater(_decode(malformedColor), throwsFormatException);
  });

  test('rejects a missing section file', () async {
    final zip = ZipEncoder().encodeBytes(
      _zipOf([
        _file('backup.csv', _metadata),
        _file('tasks.csv', 'id,name,started_at,ended_at,notes\r\n'),
        _file('task_colors.csv', 'name_key,argb\r\n'),
      ]),
    );

    await expectLater(_decode(zip), throwsFormatException);
  });
}
