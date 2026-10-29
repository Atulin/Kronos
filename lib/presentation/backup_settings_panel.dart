import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../domain/backup_preferences.dart';
import '../domain/task_backup.dart';

class BackupSettingsPanel extends StatefulWidget {
  const BackupSettingsPanel({
    super.key,
    required this.service,
    required this.onBackupImported,
  });

  final BackupService service;
  final Future<void> Function()? onBackupImported;

  @override
  State<BackupSettingsPanel> createState() => _BackupSettingsPanelState();
}

class _BackupSettingsPanelState extends State<BackupSettingsPanel> {
  BackupPreferences? _preferences;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await widget.service.loadPreferences();
    if (mounted) setState(() => _preferences = preferences);
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    if (preferences == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: preferences.enabled,
            onChanged: _busy ? null : _setEnabled,
            title: const Text('Automatic backups'),
            subtitle: const Text('Keep a scheduled JSON backup up to date'),
            secondary: const Icon(Icons.backup_outlined),
          ),
          if (preferences.enabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Frequency'),
              trailing: DropdownButton<BackupFrequency>(
                value: preferences.frequency,
                onChanged: _busy ? null : _setFrequency,
                items: [
                  for (final frequency in BackupFrequency.values)
                    DropdownMenuItem(
                      value: frequency,
                      child: Text(frequency.label),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Backup folder'),
              subtitle: Text(
                preferences.directoryName ?? 'App-private documents folder',
              ),
              trailing: TextButton(
                onPressed: _busy ? null : _chooseDirectory,
                child: const Text('Choose'),
              ),
            ),
            if (preferences.hasCustomDirectory)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _useAppStorage,
                  child: const Text('Use app storage instead'),
                ),
              ),
          ],
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('Last backup'),
            subtitle: Text(
              preferences.lastBackupAt == null
                  ? 'No backup created yet'
                  : _formatDateTime(preferences.lastBackupAt!.toLocal()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Export'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Import'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'JSON backups are not encrypted yet. Android may delay scheduled backups to save battery.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Future<void> _setEnabled(bool enabled) => _perform(() async {
    await widget.service.setEnabled(enabled);
  });

  Future<void> _setFrequency(BackupFrequency? frequency) async {
    if (frequency == null) return;
    await _perform(() => widget.service.setFrequency(frequency));
  }

  Future<void> _chooseDirectory() async {
    await _perform(() async {
      final selected = await widget.service.chooseDirectory();
      if (!selected) return;
    });
  }

  Future<void> _useAppStorage() => _perform(widget.service.useAppStorage);

  Future<void> _export() async {
    await _perform(() async {
      final saved = await widget.service.exportBackup();
      if (saved && mounted) _showMessage('Backup exported.');
    });
  }

  Future<void> _import() async {
    TaskBackup? backup;
    try {
      backup = await widget.service.pickBackup();
    } catch (error) {
      if (mounted) _showMessage('Could not read backup: $error');
      return;
    }
    if (backup == null || !mounted) return;

    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace all task data?'),
        content: Text(
          'This backup contains ${backup!.tasks.length} tasks. Importing it will replace all current tasks, task colors, and custom color swatches.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace data'),
          ),
        ],
      ),
    );
    if (shouldRestore != true || !mounted) return;

    await _perform(() async {
      await widget.service.restoreBackup(backup!);
      await widget.onBackupImported?.call();
      if (mounted) _showMessage('Backup restored.');
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      final preferences = await widget.service.loadPreferences();
      if (mounted) setState(() => _preferences = preferences);
    } catch (error) {
      if (mounted) _showMessage('Backup operation failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }
}

String _formatDateTime(DateTime value) {
  final date =
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}
