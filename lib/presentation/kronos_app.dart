import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'home_page.dart';
import 'task_view_model.dart';

class KronosApp extends StatefulWidget {
  const KronosApp({super.key, required this.viewModel});

  final TaskViewModel viewModel;

  @override
  State<KronosApp> createState() => _KronosAppState();
}

class _KronosAppState extends State<KronosApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    widget.viewModel.load().then((_) {
      if (mounted) setState(() => _themeMode = widget.viewModel.themeMode);
    });
  }

  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kronos',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: HomePage(
        viewModel: widget.viewModel,
        onThemeModeChanged: (mode) {
          setState(() => _themeMode = mode);
          widget.viewModel.setThemeMode(mode);
        },
      ),
    );
  }
}
