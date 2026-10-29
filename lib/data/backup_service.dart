import 'dart:convert';
import 'dart:io';

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
  static const _directoryChannel = MethodChannel(
    'cc.angius.kronos/backup_directory',
  );

  final TaskRepository _repository;

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
    final result = await _directoryChannel.invokeMapMethod<String, Object?>(
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
    await _directoryChannel.invokeMethod<void>('releaseBackupDirectory', {
      'uri': uri,
    });
  }

  Future<bool> exportBackup() async {
    final backup = await _repository.exportBackup();
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(backup.toJson())));
    final savedFile = await FilePicker.saveFile(
      dialogTitle: 'Export Kronos backup',
      fileName: _manualBackupFileName(backup.exportedAt),
      bytes: bytes,
      mimeType: 'application/json',
    );
    if (savedFile == null) return false;
    await _recordBackup(DateTime.now());
    return true;
  }

  Future<TaskBackup?> pickBackup() async {
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    if (!file.name.toLowerCase().endsWith('.json')) {
      throw const FormatException('Choose a Kronos JSON backup file.');
    }
    final json = jsonDecode(utf8.decode(await file.readAsBytes()));
    return TaskBackup.fromJson(json);
  }

  Future<void> restoreBackup(TaskBackup backup) async {
    await _repository.restoreBackup(backup);
  }

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

    final backup = await _repository.exportBackup();
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(backup.toJson())));
    final treeUri = preferences.directoryUri;
    if (treeUri != null) {
      await SafStream().writeFileBytes(
        treeUri,
        'kronos-automatic-backup.json',
        'application/json',
        bytes,
        overwrite: true,
      );
    } else {
      final documents = await getApplicationDocumentsDirectory();
      final backupDirectory = Directory(
        paths.join(documents.path, 'Kronos', 'Backups'),
      );
      await backupDirectory.create(recursive: true);
      final destination = File(
        paths.join(backupDirectory.path, 'kronos-automatic-backup.json'),
      );
      final temporaryFile = File('${destination.path}.tmp');
      await temporaryFile.writeAsBytes(bytes, flush: true);
      await temporaryFile.rename(destination.path);
    }
    await _recordBackup(DateTime.now());
  }

  Future<void> _recordBackup(DateTime at) =>
      _repository.saveSetting(_lastBackupKey, at.toUtc().toIso8601String());

  String _manualBackupFileName(DateTime at) {
    final timestamp = at.toUtc().toIso8601String().replaceAll(':', '-');
    return 'kronos-backup-$timestamp.json';
  }
}
