import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import 'backup_settings_panel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.backupService,
    this.onBackupImported,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final BackupService? backupService;
  final Future<void> Function()? onBackupImported;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late ThemeMode _selectedThemeMode;

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.themeMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'APPEARANCE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: _selectedThemeMode,
              onChanged: _choose,
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    title: const Text('Device default'),
                    subtitle: const Text(
                      'Follow your device appearance setting',
                    ),
                    secondary: const Icon(Icons.brightness_auto_rounded),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    title: const Text('Light'),
                    secondary: const Icon(Icons.light_mode_outlined),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    title: const Text('Dark'),
                    secondary: const Icon(Icons.dark_mode_outlined),
                  ),
                ],
              ),
            ),
          ),
          if (widget.backupService != null) ...[
            const SizedBox(height: 28),
            Text(
              'DATA & BACKUP',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            BackupSettingsPanel(
              service: widget.backupService!,
              onBackupImported: widget.onBackupImported,
            ),
          ],
        ],
      ),
    );
  }

  void _choose(ThemeMode? value) {
    if (value == null) return;
    setState(() => _selectedThemeMode = value);
    widget.onThemeModeChanged(value);
  }
}
