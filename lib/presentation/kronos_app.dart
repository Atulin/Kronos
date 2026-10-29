import 'package:flutter/material.dart';

import 'home_page.dart';
import 'task_view_model.dart';

class KronosApp extends StatefulWidget {
  const KronosApp({super.key, required this.viewModel});

  final TaskViewModel viewModel;

  @override
  State<KronosApp> createState() => _KronosAppState();
}

class _KronosAppState extends State<KronosApp> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
  }

  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF315E65);
    return MaterialApp(
      title: 'Kronos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F5),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F7F5),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      home: HomePage(viewModel: widget.viewModel),
    );
  }
}
