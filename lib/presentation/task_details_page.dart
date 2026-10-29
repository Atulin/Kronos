import 'package:flutter/material.dart';

import '../domain/task.dart';
import 'task_view_model.dart';

class TaskDetailsPage extends StatefulWidget {
  const TaskDetailsPage({
    super.key,
    required this.task,
    required this.viewModel,
  });
  final Task task;
  final TaskViewModel viewModel;

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _TaskDetailsPageState extends State<TaskDetailsPage> {
  late final TextEditingController _name;
  late DateTime _start;
  late DateTime? _end;
  late Color _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.task.name);
    _start = widget.task.startedAt;
    _end = widget.task.endedAt;
    _color = widget.viewModel.colorFor(widget.task.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime({required bool isStart}) async {
    final initial = isStart ? _start : (_end ?? DateTime.now());
    final firstDate = DateTime(2000);
    final lastDate = DateTime.now().add(const Duration(days: 365 * 20));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: isStart ? 'SELECT START DATE' : 'SELECT END DATE',
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !mounted) return;
    final value = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (isStart) {
      if (_end != null && value.isAfter(_end!)) {
        _showMessage('Start time must be before the end time.');
        return;
      }
      setState(() => _start = value);
    } else {
      if (value.isBefore(_start)) {
        _showMessage('End time must be after the start time.');
        return;
      }
      setState(() => _end = value);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a task name.');
      return;
    }
    setState(() => _saving = true);
    final updated = widget.task.copyWith(
      name: name,
      startedAt: _start,
      endedAt: _end,
      clearEndedAt: _end == null,
    );
    await widget.viewModel.updateTask(updated, color: _color);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final duration = (_end ?? widget.viewModel.now).difference(_start);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task details'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text('TASK', style: _eyebrow(context)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 26),
          Text('TIME', style: _eyebrow(context)),
          const SizedBox(height: 8),
          _DateTimeRow(
            title: 'Started',
            value: _start,
            onTap: () => _selectDateTime(isStart: true),
          ),
          const Divider(height: 1),
          if (_end == null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Still running'),
              subtitle: const Text(
                'Set an end time when you finish this task.',
              ),
              trailing: TextButton(
                onPressed: () => _selectDateTime(isStart: false),
                child: const Text('Set end'),
              ),
            )
          else ...[
            _DateTimeRow(
              title: 'Ended',
              value: _end!,
              onTap: () => _selectDateTime(isStart: false),
            ),
            const Divider(height: 1),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _end = null),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('Mark as still running'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Duration')),
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text('COLOR', style: _eyebrow(context)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in taskColors)
                InkWell(
                  onTap: () => setState(() => _color = color),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _color.toARGB32() == color.toARGB32()
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                    child: _color.toARGB32() == color.toARGB32()
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 40),
          OutlinedButton.icon(
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete task'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle? _eyebrow(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      );

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('“${widget.task.name}” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await widget.viewModel.deleteTask(widget.task);
    if (!context.mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('Task deleted')));
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.title,
    required this.value,
    required this.onTap,
  });
  final String title;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(_dateTime(value)),
    trailing: const Icon(Icons.edit_outlined, size: 19),
    onTap: onTap,
  );
}

String _dateTime(DateTime value) {
  final date =
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return '$date  ·  $time';
}

String _formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '$minutes min';
  return '$hours hr ${minutes.toString().padLeft(2, '0')} min';
}
