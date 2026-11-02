import 'package:csv/csv.dart';

import 'task.dart';

const backupFormatVersion = 1;

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

const _tasksSection = 'tasks';
const _colorsSection = 'task_colors';
const _customColorsSection = 'custom_colors';
const _sectionColumns = {
  _tasksSection: ['id', 'name', 'started_at', 'ended_at', 'notes'],
  _colorsSection: ['name_key', 'argb'],
  _customColorsSection: ['argb'],
};
const _eol = '\r\n';

/// Encodes [entries] as CSV lines.
///
/// The first line is `#kronos-backup,<version>,<exportedAt>`. Each section
/// starts with a `#<section>` line naming its columns, so rows carry no
/// per-row type. Lines starting with `#` are not RFC 4180 rows; decoders
/// that don't know them can skip them.
Stream<String> encodeBackup(Stream<BackupEntry> entries) async* {
  var section = '';
  await for (final entry in entries) {
    switch (entry) {
      case BackupHeader(:final exportedAt):
        yield '#kronos-backup,$backupFormatVersion,'
            '${exportedAt.toUtc().toIso8601String()}$_eol';
      case BackupTaskEntry(:final task):
        if (section != _tasksSection) {
          section = _tasksSection;
          yield _sectionLine(_tasksSection);
        }
        yield _row([
          task.id,
          task.name,
          task.startedAt.toIso8601String(),
          task.endedAt?.toIso8601String() ?? '',
          task.notes,
        ]);
      case BackupColorEntry(:final key, :final argb):
        if (section != _colorsSection) {
          section = _colorsSection;
          yield _sectionLine(_colorsSection);
        }
        yield _row([key, argb]);
      case BackupCustomColorEntry(:final argb):
        if (section != _customColorsSection) {
          section = _customColorsSection;
          yield _sectionLine(_customColorsSection);
        }
        yield _row([argb]);
    }
  }
}

/// Decodes CSV text produced by [encodeBackup], one entry at a time.
Stream<BackupEntry> decodeBackup(Stream<String> text) async* {
  var headerSeen = false;
  var section = '';
  await for (final row in const CsvDecoder(fieldDelimiter: ',').bind(text)) {
    final fields = row.map((field) => '$field').toList();
    final first = fields.first;
    if (first.startsWith('#')) {
      final name = first.substring(1);
      if (name == 'kronos-backup') {
        if (headerSeen ||
            fields.length != 3 ||
            int.tryParse(fields[1]) != backupFormatVersion) {
          throw const FormatException('Unsupported Kronos backup version.');
        }
        headerSeen = true;
        yield BackupHeader(_date(fields[2]));
      } else if (_sectionColumns.containsKey(name)) {
        final columns = fields.sublist(1);
        if (!_sameColumns(columns, _sectionColumns[name]!)) {
          throw const FormatException('Backup has an unexpected layout.');
        }
        section = name;
      }
      continue;
    }

    if (!headerSeen) {
      throw const FormatException('Not a Kronos backup file.');
    }
    switch (section) {
      case _tasksSection:
        yield BackupTaskEntry(_task(fields));
      case _colorsSection:
        if (fields.length != 2 || fields[0].isEmpty) {
          throw const FormatException('Backup contains an invalid task color.');
        }
        yield BackupColorEntry(fields[0], _argb(fields[1]));
      case _customColorsSection:
        if (fields.length != 1) {
          throw const FormatException('Backup contains invalid custom colors.');
        }
        yield BackupCustomColorEntry(_argb(fields[0]));
      default:
        throw const FormatException('Backup contains a row outside a section.');
    }
  }
  if (!headerSeen) {
    throw const FormatException('Not a Kronos backup file.');
  }
}

String _sectionLine(String name) =>
    '#$name,${_sectionColumns[name]!.join(',')}$_eol';

String _row(List<Object> fields) =>
    '${const CsvEncoder().convert([fields])}$_eol';

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
