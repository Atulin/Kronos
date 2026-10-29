import 'package:flutter/material.dart';

import '../domain/task_filter.dart';

class SearchFilterSheet extends StatefulWidget {
  const SearchFilterSheet({super.key, required this.initialFilter});

  final TaskFilter initialFilter;

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late final TextEditingController _query;
  DateTime? _startedAfter;
  DateTime? _startedBefore;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialFilter.query);
    _startedAfter = widget.initialFilter.startedAfter;
    _startedBefore = widget.initialFilter.startedBefore;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Search and filter',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _apply(),
                  decoration: InputDecoration(
                    labelText: 'Task name',
                    hintText: 'Search completed tasks',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search text',
                            onPressed: () {
                              _query.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear_rounded),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                Text(
                  'STARTED BETWEEN',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Card(
                  child: Column(
                    children: [
                      _DateBoundTile(
                        title: 'From',
                        value: _startedAfter,
                        onTap: () => _selectDateTime(isLowerBound: true),
                        onClear: _startedAfter == null
                            ? null
                            : () => setState(() => _startedAfter = null),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _DateBoundTile(
                        title: 'To',
                        value: _startedBefore,
                        onTap: () => _selectDateTime(isLowerBound: false),
                        onClear: _startedBefore == null
                            ? null
                            : () => setState(() => _startedBefore = null),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_rounded),
                      label: const Text('Clear filters'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _apply,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateTime({required bool isLowerBound}) async {
    final current = isLowerBound ? _startedAfter : _startedBefore;
    final initial = current ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: isLowerBound
          ? 'SELECT STARTING AFTER'
          : 'SELECT STARTING BEFORE',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (isLowerBound &&
        _startedBefore != null &&
        selected.isAfter(_startedBefore!)) {
      _showRangeError('The “From” time must be before the “To” time.');
      return;
    }
    if (!isLowerBound &&
        _startedAfter != null &&
        selected.isBefore(_startedAfter!)) {
      _showRangeError('The “To” time must be after the “From” time.');
      return;
    }
    setState(() {
      if (isLowerBound) {
        _startedAfter = selected;
      } else {
        _startedBefore = selected;
      }
    });
  }

  void _showRangeError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _clearFilters() => Navigator.pop(context, const TaskFilter());

  void _apply() => Navigator.pop(
    context,
    TaskFilter(
      query: _query.text.trim(),
      startedAfter: _startedAfter,
      startedBefore: _startedBefore,
    ),
  );
}

class _DateBoundTile extends StatelessWidget {
  const _DateBoundTile({
    required this.title,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String title;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.calendar_today_outlined),
    title: Text(title),
    subtitle: Text(value == null ? 'Any time' : _formatDateTime(value!)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onClear != null)
          IconButton(
            tooltip: 'Clear $title time',
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded),
          ),
        const Icon(Icons.edit_calendar_outlined),
      ],
    ),
    onTap: onTap,
  );
}

String _formatDateTime(DateTime value) {
  final date =
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}
