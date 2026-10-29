import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../domain/task.dart';
import 'date_time_wheel_picker.dart';
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
  late final TextEditingController _notes;
  late DateTime _start;
  late DateTime? _end;
  Color? _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.task.name);
    _notes = TextEditingController(text: widget.task.notes);
    _start = widget.task.startedAt;
    _end = widget.task.endedAt;
    _color = widget.viewModel.colorFor(widget.task.name);
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime({required bool isStart}) async {
    final initial = isStart ? _start : (_end ?? DateTime.now());
    final value = await showDialog<DateTime>(
      context: context,
      builder: (_) => DateTimeWheelPicker(
        initialDateTime: initial,
        title: isStart ? 'Start time' : 'End time',
      ),
    );
    if (value == null || !mounted) return;
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
      notes: _notes.text,
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
              Tooltip(
                message: 'No color',
                child: InkWell(
                  onTap: () => setState(() => _color = null),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == null
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: _color == null ? 3 : 1,
                      ),
                    ),
                    child: ClipOval(
                      child: CustomPaint(
                        key: const Key('no-color-cross'),
                        size: const Size(38, 38),
                        painter: _NoColorCrossPainter(),
                      ),
                    ),
                  ),
                ),
              ),
              for (final color in [
                ...taskColors,
                ...widget.viewModel.customColors,
              ])
                InkWell(
                  onTap: () => setState(() => _color = color),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: _color?.toARGB32() == color.toARGB32()
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                    child: _color?.toARGB32() == color.toARGB32()
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                ),
              Tooltip(
                message: 'Add custom color',
                child: InkWell(
                  onTap: _addCustomColor,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    child: const Icon(Icons.add_rounded, size: 22),
                  ),
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
          const SizedBox(height: 28),
          Text('NOTES', style: _eyebrow(context)),
          const SizedBox(height: 10),
          TextField(
            key: const Key('task-notes'),
            controller: _notes,
            minLines: 4,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Add notes about this task…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
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

  Future<void> _addCustomColor() async {
    var pickerColor = _color ?? taskColors.first;
    final pickerWidth = (MediaQuery.sizeOf(context).width - 128)
        .clamp(180.0, 280.0)
        .toDouble();
    final selected = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add custom color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) =>
                  setDialogState(() => pickerColor = color),
              enableAlpha: false,
              labelTypes: const [],
              colorPickerWidth: pickerWidth,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, pickerColor),
              child: const Text('Add swatch'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await widget.viewModel.addCustomColor(selected);
    if (!mounted) return;
    setState(() => _color = selected);
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

class _NoColorCrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD32F2F)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(0, 0), Offset(size.width, size.height), paint)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _NoColorCrossPainter oldDelegate) => false;
}
