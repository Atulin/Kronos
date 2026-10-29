import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'backup_service.dart';
import 'task_repository.dart';

// NOTE: Track workmanager_android's KGP migration warning in
// https://github.com/Atulin/Kronos/issues/1.
Future<void> initializeBackupWorker() =>
    Workmanager().initialize(backupCallbackDispatcher);

@pragma('vm:entry-point')
void backupCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    if (task != BackupService.taskName) return true;

    final repository = SqliteTaskRepository();
    try {
      await BackupService(repository).runScheduledBackup();
      return true;
    } catch (_) {
      return false;
    } finally {
      await repository.close();
    }
  });
}
