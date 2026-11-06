import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';

import 'task.dart';
import 'task_reminder.dart';

/// Version of the backup layout.
///
/// Version 2 is a ZIP archive of one RFC 4180 CSV per content type. Version
/// 1 was a single CSV file using `#`-directives for metadata and can no
/// longer be imported.
const backupFormatVersion = 2;

sealed class BackupEntry {
  const BackupEntry();
}

final class BackupHeader extends BackupEntry {
  const BackupHeader(this.exportedAt);

  final DateTime exportedAt;
}

final class BackupTaskEntry extends BackupEntry {
  const BackupTaskEntry(this.task);

  final Task task;
}

final class BackupColorEntry extends BackupEntry {
  const BackupColorEntry(this.key, this.argb);

  final String key;
  final int argb;
}

final class BackupCustomColorEntry extends BackupEntry {
  const BackupCustomColorEntry(this.argb);

  final int argb;
}

final class BackupReminderEntry extends BackupEntry {
  const BackupReminderEntry(this.key, this.reminder);

  final String key;
  final TaskReminder reminder;
}

const _backupFileName = 'backup.csv';
const _tasksFileName = 'tasks.csv';
const _colorsFileName = 'task_colors.csv';
const _customColorsFileName = 'custom_colors.csv';
const _remindersFileName = 'task_reminders.csv';

const _tasksColumns = ['id', 'name', 'started_at', 'ended_at', 'notes'];
const _colorsColumns = ['name_key', 'argb'];
const _customColorsColumns = ['argb'];
const _remindersColumns = ['name_key', 'minutes', 'repeats', 'sound'];
const _backupColumns = ['format_version', 'exported_at'];
const _eol = '\r\n';

/// Encodes [entries] as a ZIP archive of one CSV per content type.
///
/// `backup.csv` holds the export metadata (format version and timestamp),
/// while `tasks.csv`, `task_colors.csv`, and `custom_colors.csv` hold the
/// rows. Every file starts with an RFC 4180 header row.
Future<Uint8List> encodeBackup(Stream<BackupEntry> entries) async {
  var exportedAt = DateTime.now();
  final tasks = <Task>[];
  final colors = <BackupColorEntry>[];
  final customColors = <BackupCustomColorEntry>[];
  final reminders = <BackupReminderEntry>[];

  await for (final entry in entries) {
    switch (entry) {
      case BackupHeader(exportedAt: final at):
        exportedAt = at;
      case BackupTaskEntry(:final task):
        tasks.add(task);
      case BackupColorEntry(:final key, :final argb):
        colors.add(BackupColorEntry(key, argb));
      case BackupCustomColorEntry(:final argb):
        customColors.add(BackupCustomColorEntry(argb));
      case BackupReminderEntry(:final key, :final reminder):
        reminders.add(BackupReminderEntry(key, reminder));
    }
  }

  final zip = Archive()
    ..addFile(
      _csvFile(_backupFileName, [
        _backupColumns,
        [backupFormatVersion, exportedAt.toUtc().toIso8601String()],
      ]),
    )
    ..addFile(
      _csvFile(_tasksFileName, [
        _tasksColumns,
        for (final task in tasks)
          [
            task.id,
            task.name,
            task.startedAt.toUtc().toIso8601String(),
            task.endedAt?.toUtc().toIso8601String() ?? '',
            task.notes,
          ],
      ]),
    )
    ..addFile(
      _csvFile(_colorsFileName, [
        _colorsColumns,
        for (final color in colors) [color.key, color.argb],
      ]),
    )
    ..addFile(
      _csvFile(_customColorsFileName, [
        _customColorsColumns,
        for (final color in customColors) [color.argb],
      ]),
    )
    ..addFile(
      _csvFile(_remindersFileName, [
        _remindersColumns,
        for (final reminder in reminders)
          [
            reminder.key,
            reminder.reminder.minutes,
            reminder.reminder.repeats ? 1 : 0,
            reminder.reminder.sound,
          ],
      ]),
    );

  return ZipEncoder().encodeBytes(zip);
}

/// Decodes the ZIP archive produced by [encodeBackup], one entry at a time.
Stream<BackupEntry> decodeBackup(Stream<List<int>> bytes) async* {
  final buffer = BytesBuilder(copy: true);
  await for (final chunk in bytes) {
    buffer.add(chunk);
  }
  final data = buffer.takeBytes();

  final Map<String, ArchiveFile> files;
  try {
    files = {
      for (final file in ZipDecoder().decodeBytes(data)) file.name: file,
    };
  } catch (_) {
    throw const FormatException('Not a Kronos backup file.');
  }

  final metadata = await _rowsOf(files, _backupFileName, _backupColumns);
  if (metadata.length != 1 ||
      int.tryParse(metadata[0][0]) != backupFormatVersion) {
    throw const FormatException('Unsupported Kronos backup version.');
  }
  yield BackupHeader(_date(metadata[0][1]));

  for (final row in await _rowsOf(files, _tasksFileName, _tasksColumns)) {
    yield BackupTaskEntry(_task(row));
  }
  for (final row in await _rowsOf(files, _colorsFileName, _colorsColumns)) {
    if (row.length != 2 || row[0].isEmpty) {
      throw const FormatException('Backup contains an invalid task color.');
    }
    yield BackupColorEntry(row[0], _argb(row[1]));
  }
  for (final row in await _rowsOf(
    files,
    _customColorsFileName,
    _customColorsColumns,
  )) {
    if (row.length != 1) {
      throw const FormatException('Backup contains invalid custom colors.');
    }
    yield BackupCustomColorEntry(_argb(row[0]));
  }
  // Reminders were added after format version 2; older backups legitimately
  // have no section for them.
  final reminderRows = files[_remindersFileName] == null
      ? const <List<String>>[]
      : await _rowsOf(files, _remindersFileName, _remindersColumns);
  for (final row in reminderRows) {
    yield BackupReminderEntry(
      _reminderKey(row[0]),
      _reminder(row[1], row[2], row[3]),
    );
  }
}

ArchiveFile _csvFile(String name, List<List<Object?>> rows) =>
    _zipFile(name, utf8.encode('${const CsvEncoder().convert(rows)}$_eol'));

ArchiveFile _zipFile(String name, List<int> content) =>
    ArchiveFile(name, content.length, content);

/// Reads [name] from [files] and returns its validated data rows.
Future<List<List<String>>> _rowsOf(
  Map<String, ArchiveFile> files,
  String name,
  List<String> columns,
) async {
  final file = files[name];
  if (file == null) {
    throw const FormatException('Kronos backup is missing a section file.');
  }
  final text = utf8.decode(file.content, allowMalformed: true);
  final rows = await const CsvDecoder().bind(Stream.value(text)).toList();
  if (rows.isEmpty || !_sameColumns(_stringRow(rows[0]), columns)) {
    throw const FormatException('Backup has an unexpected layout.');
  }
  return [for (final row in rows.skip(1)) _stringRow(row)];
}

List<String> _stringRow(List<dynamic> fields) => [
  for (final field in fields) '$field',
];

bool _sameColumns(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

Task _task(List<String> fields) {
  if (fields.length != 5) {
    throw const FormatException('Backup contains a malformed task.');
  }
  final id = fields[0];
  final name = fields[1];
  final startedAt = _date(fields[2]);
  final endedAt = fields[3].isEmpty ? null : _date(fields[3]);
  if (id.isEmpty ||
      name.trim().isEmpty ||
      (endedAt != null && endedAt.isBefore(startedAt))) {
    throw const FormatException('Backup contains an invalid task.');
  }
  return Task(
    id: id,
    name: name,
    startedAt: startedAt,
    endedAt: endedAt,
    notes: fields[4],
  );
}

DateTime _date(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('Backup contains an invalid timestamp.');
  }
  return parsed;
}

int _argb(String value) {
  final argb = int.tryParse(value);
  if (argb == null || argb < 0 || argb > 0xFFFFFFFF) {
    throw const FormatException('Backup contains an invalid color.');
  }
  return argb;
}

String _reminderKey(String value) {
  if (value.isEmpty) {
    throw const FormatException('Backup contains an invalid task reminder.');
  }
  return value;
}

TaskReminder _reminder(String minutesField, String repeatsField, String sound) {
  final minutes = int.tryParse(minutesField);
  final repeats = switch (repeatsField) {
    '0' => false,
    '1' => true,
    _ => throw const FormatException(
      'Backup contains an invalid task reminder.',
    ),
  };
  if (minutes == null || minutes < 1 || minutes > 525600) {
    throw const FormatException('Backup contains an invalid task reminder.');
  }
  return TaskReminder(
    interval: Duration(minutes: minutes),
    repeats: repeats,
    sound: sound,
  );
}
