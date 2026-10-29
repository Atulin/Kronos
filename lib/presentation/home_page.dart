import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../domain/task.dart';
import '../domain/task_filter.dart';
import 'search_filter_sheet.dart';
import 'settings_page.dart';
import 'task_details_page.dart';
import 'task_view_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.viewModel,
    required this.onThemeModeChanged,
    this.backupService,
  });

  final TaskViewModel viewModel;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final BackupService? backupService;

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
        actions: [
          ListenableBuilder(
            listenable: widget.viewModel,
            builder: (context, _) => IconButton(
              tooltip: 'Search and filter',
              onPressed: widget.viewModel.isLoaded ? _openSearch : null,
              icon: Icon(
                widget.viewModel.filter.isActive
                    ? Icons.manage_search_rounded
                    : Icons.search_rounded,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsPage(
                  themeMode: widget.viewModel.themeMode,
                  onThemeModeChanged: widget.onThemeModeChanged,
                  backupService: widget.backupService,
                  onBackupImported: widget.viewModel.load,
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
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
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 400 &&
                        widget.viewModel.hasMoreCompleted) {
                      unawaited(widget.viewModel.loadMoreCompleted());
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    key: const Key('task-list'),
                    slivers: [
                      const SliverToBoxAdapter(
                        child: _SectionHeading(title: 'COMPLETED'),
                      ),
                      if (widget.viewModel.isFiltering)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (completed.isEmpty)
                        SliverToBoxAdapter(
                          child: _EmptyCompleted(
                            filterActive: widget.viewModel.filter.isActive,
                          ),
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
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
                      if (widget.viewModel.isLoadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                    ],
                  ),
                ),
              ),
              _AddTaskPanel(
                controller: _input,
                focusNode: _focus,
                runningTasks: running,
                colorFor: widget.viewModel.colorFor,
                now: widget.viewModel.now,
                onStop: widget.viewModel.stopTask,
                onOpen: (task) => _openDetails(context, task),
                onDelete: (task) => _confirmDelete(context, task),
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

  Future<void> _openSearch() async {
    final filter = await showModalBottomSheet<TaskFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SearchFilterSheet(initialFilter: widget.viewModel.filter),
    );
    if (filter == null || !mounted) return;
    await widget.viewModel.applyFilter(filter);
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
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  final Color? color;
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
  final Color? color;
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
          Icon(
            Icons.chevron_right_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
  final Color? color;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(width: 5, height: 58, color: color ?? Colors.transparent),
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
  const _EmptyCompleted({required this.filterActive});

  final bool filterActive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 35, 24, 35),
    child: Column(
      children: [
        Icon(
          Icons.hourglass_empty_rounded,
          size: 32,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 10),
        Text(
          filterActive
              ? 'No completed tasks match these filters'
              : 'No completed tasks yet',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _AddTaskPanel extends StatelessWidget {
  const _AddTaskPanel({
    required this.controller,
    required this.focusNode,
    required this.runningTasks,
    required this.colorFor,
    required this.now,
    required this.onStop,
    required this.onOpen,
    required this.onDelete,
    required this.suggestions,
    required this.onChanged,
    required this.onStart,
    required this.onSuggestion,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<Task> runningTasks;
  final Color? Function(String name) colorFor;
  final DateTime now;
  final ValueChanged<Task> onStop;
  final ValueChanged<Task> onOpen;
  final ValueChanged<Task> onDelete;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final VoidCallback onStart;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (runningTasks.isNotEmpty) ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.viewInsetsOf(context).bottom > 0
                      ? 90
                      : 190,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: runningTasks.length,
                  itemBuilder: (context, index) {
                    final task = runningTasks[index];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RunningTaskTile(
                          task: task,
                          color: colorFor(task.name),
                          now: now,
                          onStop: () => onStop(task),
                          onTap: () => onOpen(task),
                          onDelete: () => onDelete(task),
                        ),
                        if (index < runningTasks.length - 1)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
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
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
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
