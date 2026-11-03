import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:workmanager/workmanager.dart';

import '../domain/backup_preferences.dart';
import '../domain/task_backup.dart';
import 'task_repository.dart';

class BackupService {
  BackupService(this._repository);

  static const taskName = 'kronos.automatic_backup';
  static const uniqueTaskName = 'kronos-automatic-backup';
  static const _enabledKey = 'automatic_backups_enabled';
  static const _frequencyKey = 'automatic_backup_frequency';
  static const _directoryUriKey = 'automatic_backup_directory_uri';
  static const _directoryNameKey = 'automatic_backup_directory_name';
  static const _lastBackupKey = 'last_backup_at';
  static const _scheduledFrequencyKey = 'scheduled_backup_frequency';
  static const _backupChannel = MethodChannel(
    'cc.angius.kronos/backup_directory',
  );
  static const _chunkSize = 64 * 1024;
  static const _extension = 'zip';
  static const _mimeType = 'application/zip';
  static const _automaticBackupFileName = 'kronos-automatic-backup.zip';

  final TaskRepository _repository;
  final _saf = SafStream();

  Future<BackupPreferences> loadPreferences() async {
    final settings = await Future.wait([
      _repository.loadSetting(_enabledKey),
      _repository.loadSetting(_frequencyKey),
      _repository.loadSetting(_directoryUriKey),
      _repository.loadSetting(_directoryNameKey),
      _repository.loadSetting(_lastBackupKey),
    ]);
    final backupAt = DateTime.tryParse(settings[4] ?? '');
    return BackupPreferences(
      enabled: settings[0] == null ? true : settings[0] == 'true',
      frequency: BackupFrequency.parse(settings[1]),
      directoryUri: settings[2],
      directoryName: settings[3],
      lastBackupAt: backupAt,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    await _repository.saveSetting(_enabledKey, enabled.toString());
    await syncSchedule();
  }

  Future<void> setFrequency(BackupFrequency frequency) async {
    await _repository.saveSetting(_frequencyKey, frequency.name);
    await syncSchedule();
  }

  Future<bool> chooseDirectory() async {
    final result = await _backupChannel.invokeMapMethod<String, Object?>(
      'pickBackupDirectory',
    );
    final uri = result?['uri'];
    if (uri is! String || uri.isEmpty) return false;
    final oldUri = await _repository.loadSetting(_directoryUriKey);
    if (oldUri != null && oldUri != uri) {
      await _releaseDirectoryPermission(oldUri);
    }
    await _repository.saveSetting(_directoryUriKey, uri);
    final name = result?['name'];
    if (name is String && name.isNotEmpty) {
      await _repository.saveSetting(_directoryNameKey, name);
    }
    return true;
  }

  Future<void> useAppStorage() async {
    final oldUri = await _repository.loadSetting(_directoryUriKey);
    if (oldUri != null) await _releaseDirectoryPermission(oldUri);
    await _repository.deleteSetting(_directoryUriKey);
    await _repository.deleteSetting(_directoryNameKey);
  }

  Future<void> _releaseDirectoryPermission(String uri) async {
    await _backupChannel.invokeMethod<void>('releaseBackupDirectory', {
      'uri': uri,
    });
  }

  Future<bool> exportBackup() async {
    final uri = await _backupChannel.invokeMethod<String>('createBackupFile', {
      'fileName': _manualBackupFileName(DateTime.now()),
      'mimeType': _mimeType,
    });
    if (uri == null) return false;
    final stream = await _saf.startWriteFileUriStream(uri);
    await _writeSession(stream.session, _chunks(_encodedBackup()));
    await _recordBackup(DateTime.now());
    return true;
  }

  Future<PlatformFile?> pickBackupFile() async {
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    if (!file.name.toLowerCase().endsWith('.$_extension')) {
      throw const FormatException('Choose a Kronos ZIP backup file.');
    }
    return file;
  }

  Future<void> importBackup(PlatformFile file) => _repository.restoreBackup(
    decodeBackup(file.readAsByteStream()),
  );

  Future<void> syncSchedule() async {
    final preferences = await loadPreferences();
    final wasScheduled = await Workmanager().isScheduledByUniqueName(
      uniqueTaskName,
    );
    final previousFrequency = await _repository.loadSetting(
      _scheduledFrequencyKey,
    );

    if (!preferences.enabled) {
      if (wasScheduled) await Workmanager().cancelByUniqueName(uniqueTaskName);
      await _repository.deleteSetting(_scheduledFrequencyKey);
      return;
    }
    if (wasScheduled && previousFrequency == preferences.frequency.name) return;

    if (wasScheduled) await Workmanager().cancelByUniqueName(uniqueTaskName);
    await Workmanager().registerPeriodicTask(
      uniqueTaskName,
      taskName,
      frequency: preferences.frequency.interval,
    );
    await _repository.saveSetting(
      _scheduledFrequencyKey,
      preferences.frequency.name,
    );
  }

  Future<void> runScheduledBackup() async {
    final preferences = await loadPreferences();
    if (!preferences.enabled) return;

    final treeUri = preferences.directoryUri;
    if (treeUri != null) {
      final stream = await _saf.startWriteStream(
        treeUri,
        _automaticBackupFileName,
        _mimeType,
        overwrite: true,
      );
      await _writeSession(stream.session, _chunks(_encodedBackup()));
    } else {
      final documents = await getApplicationDocumentsDirectory();
      final backupDirectory = Directory(
        paths.join(documents.path, 'Kronos', 'Backups'),
      );
      await backupDirectory.create(recursive: true);
      final destination = File(
        paths.join(backupDirectory.path, _automaticBackupFileName),
      );
      final temporaryFile = File('${destination.path}.tmp');
      final sink = temporaryFile.openWrite();
      try {
        await sink.addStream(_chunks(_encodedBackup()));
      } finally {
        await sink.close();
      }
      await temporaryFile.rename(destination.path);
    }
    await _recordBackup(DateTime.now());
  }

  Stream<List<int>> _encodedBackup() async* {
    yield await encodeBackup(_repository.exportBackupEntries());
  }

  /// Groups small encoded pieces into chunks of about [_chunkSize] bytes so
  /// that each platform call writes a useful amount of data.
  static Stream<Uint8List> _chunks(Stream<List<int>> bytes) async* {
    final buffer = BytesBuilder(copy: false);
    await for (final part in bytes) {
      buffer.add(part);
      if (buffer.length >= _chunkSize) yield buffer.takeBytes();
    }
    if (buffer.isNotEmpty) yield buffer.takeBytes();
  }

  Future<void> _writeSession(String session, Stream<Uint8List> chunks) async {
    try {
      await for (final chunk in chunks) {
        await _saf.writeChunk(session, chunk);
      }
    } finally {
      await _saf.endWriteStream(session);
    }
  }

  Future<void> _recordBackup(DateTime at) =>
      _repository.saveSetting(_lastBackupKey, at.toUtc().toIso8601String());

  String _manualBackupFileName(DateTime at) {
    final timestamp = at.toUtc().toIso8601String().replaceAll(':', '-');
    return 'kronos-backup-$timestamp.$_extension';
  }
}
