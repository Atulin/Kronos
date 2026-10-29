import 'package:flutter/material.dart';

import '../domain/task.dart';
import 'task_details_page.dart';
import 'task_view_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.viewModel});

  final TaskViewModel viewModel;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start(String name) async {
    await widget.viewModel.startTask(name);
    _input.clear();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            Icon(Icons.schedule_rounded, size: 26),
            SizedBox(width: 10),
            Text(
              'Kronos',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          if (!widget.viewModel.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final running = widget.viewModel.runningTasks;
          final completed = widget.viewModel.completedTasks;
          final grouped = <DateTime, List<Task>>{};
          for (final task in completed) {
            final day = DateTime(
              task.startedAt.year,
              task.startedAt.month,
              task.startedAt.day,
            );
            (grouped[day] ??= []).add(task);
          }

          return Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  key: const Key('task-list'),
                  slivers: [
                    if (running.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                        child: _SectionHeading(title: 'IN PROGRESS'),
                      ),
                      SliverList.builder(
                        itemCount: running.length,
                        itemBuilder: (context, index) => _RunningTaskTile(
                          task: running[index],
                          color: widget.viewModel.colorFor(running[index].name),
                          onStop: () =>
                              widget.viewModel.stopTask(running[index]),
                          onTap: () => _openDetails(context, running[index]),
                          onDelete: () =>
                              _confirmDelete(context, running[index]),
                          now: widget.viewModel.now,
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(
                      child: _SectionHeading(title: 'COMPLETED'),
                    ),
                    if (completed.isEmpty)
                      SliverToBoxAdapter(
                        child: _EmptyCompleted(hasRunning: running.isNotEmpty),
                      )
                    else
                      for (final entry in grouped.entries) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 12, 22, 5),
                            child: Text(
                              _dateLabel(entry.key),
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: const Color(0xFF75817D),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                        SliverList.builder(
                          itemCount: entry.value.length,
                          itemBuilder: (context, index) {
                            final task = entry.value[index];
                            return _CompletedTaskTile(
                              task: task,
                              color: widget.viewModel.colorFor(task.name),
                              onTap: () => _openDetails(context, task),
                              onDelete: () => _confirmDelete(context, task),
                            );
                          },
                        ),
                      ],
                    const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  ],
                ),
              ),
              _AddTaskPanel(
                controller: _input,
                focusNode: _focus,
                suggestions: widget.viewModel.suggestionsFor(_input.text),
                onChanged: (_) => setState(() {}),
                onStart: () => _start(_input.text),
                onSuggestion: _start,
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDetails(BuildContext context, Task task) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TaskDetailsPage(task: task, viewModel: widget.viewModel),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Task task) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('“${task.name}” will be permanently removed.'),
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
    if (shouldDelete == true && context.mounted) {
      await widget.viewModel.deleteTask(task);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Task deleted')));
      }
    }
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 12, 22, 7),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: const Color(0xFF75817D),
        letterSpacing: 1.15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _RunningTaskTile extends StatelessWidget {
  const _RunningTaskTile({
    required this.task,
    required this.color,
    required this.onStop,
    required this.onTap,
    required this.onDelete,
    required this.now,
  });

  final Task task;
  final Color color;
  final VoidCallback onStop;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final DateTime now;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: onDelete,
    child: _TaskCard(
      color: color,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              task.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            _duration(task.durationAt(now)),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Stop ${task.name}',
            onPressed: onStop,
            icon: const Icon(Icons.stop_rounded, size: 19),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    ),
  );
}

class _CompletedTaskTile extends StatelessWidget {
  const _CompletedTaskTile({
    required this.task,
    required this.color,
    required this.onTap,
    required this.onDelete,
  });
  final Task task;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: onDelete,
    child: _TaskCard(
      color: color,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              task.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            _duration(task.durationAt(task.endedAt!)),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA39F)),
        ],
      ),
    ),
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.color,
    required this.onTap,
    required this.child,
  });
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(width: 5, height: 58, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyCompleted extends StatelessWidget {
  const _EmptyCompleted({required this.hasRunning});
  final bool hasRunning;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 35, 24, 35),
    child: Column(
      children: [
        Icon(
          Icons.hourglass_empty_rounded,
          size: 32,
          color: Colors.blueGrey.shade300,
        ),
        const SizedBox(height: 10),
        Text(
          hasRunning ? 'Nothing completed yet' : 'Start something to get going',
          style: const TextStyle(color: Color(0xFF78837F)),
        ),
      ],
    ),
  );
}

class _AddTaskPanel extends StatelessWidget {
  const _AddTaskPanel({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.onChanged,
    required this.onStart,
    required this.onSuggestion,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final VoidCallback onStart;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (focusNode.hasFocus && suggestions.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.history_rounded, size: 20),
                    title: Text(suggestions[index]),
                    onTap: () => onSuggestion(suggestions[index]),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    onSubmitted: (_) => onStart(),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'What are you working on?',
                      prefixIcon: const Icon(Icons.add_task_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF4F6F4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: controller.text.trim().isEmpty ? null : onStart,
                  tooltip: 'Start task',
                  icon: const Icon(Icons.play_arrow_rounded),
                  style: IconButton.styleFrom(fixedSize: const Size(52, 52)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _dateLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'TODAY';
  if (day == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[day.month - 1]} ${day.day}, ${day.year}'.toUpperCase();
}

String _duration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${duration.inMinutes}:$seconds';
}
