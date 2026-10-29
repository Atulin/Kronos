import 'dart:async';

import 'package:flutter/material.dart';

import 'data/backup_service.dart';
import 'data/backup_worker.dart';
import 'data/task_repository.dart';
import 'presentation/kronos_app.dart';
import 'presentation/task_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackupWorker();
  final repository = SqliteTaskRepository();
  final backupService = BackupService(repository);
  runApp(
    KronosApp(
      viewModel: TaskViewModel(repository),
      backupService: backupService,
    ),
  );
  unawaited(backupService.syncSchedule());
}
