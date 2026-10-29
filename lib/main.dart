import 'package:flutter/material.dart';

import 'data/task_repository.dart';
import 'presentation/kronos_app.dart';
import 'presentation/task_view_model.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = SqliteTaskRepository();
  runApp(KronosApp(viewModel: TaskViewModel(repository)));
}
