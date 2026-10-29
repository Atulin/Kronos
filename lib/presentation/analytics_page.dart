import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/task_analytics.dart';
import 'date_time_wheel_picker.dart';
import 'duration_bar_chart.dart';
import 'task_view_model.dart';

enum _AnalyticsPeriod {
  day('Day'),
  week('Week'),
  month('Month'),
  year('Year'),
  total('Total'),
  custom('Custom range');

  const _AnalyticsPeriod(this.label);
  final String label;
}

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key, required this.viewModel});

  final TaskViewModel viewModel;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String? _taskName;
  AnalyticsMetric _metric = AnalyticsMetric.taskDuration;
  _AnalyticsPeriod _period = _AnalyticsPeriod.month;
  late DateTime _customStart;
  late DateTime _customEnd;
  TaskAnalytics? _analytics;
  bool _isLoading = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _customStart = DateTime(now.year, now.month);
    _customEnd = now;
    final names = widget.viewModel.taskNames;
    _taskName = names.isEmpty ? null : names.first;
    if (_taskName != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadAnalytics());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.viewModel.taskNames;
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: names.isEmpty
          ? const Center(child: Text('Start tracking tasks to see analytics.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: names.contains(_taskName)
                      ? _taskName
                      : names.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Task',
                    prefixIcon: Icon(Icons.task_alt_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final name in names)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (name) {
                    if (name == null) return;
                    setState(() => _taskName = name);
                    unawaited(_loadAnalytics());
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final metric in AnalyticsMetric.values)
                      ChoiceChip(
                        label: Text(_metricLabel(metric)),
                        selected: _metric == metric,
                        onSelected: (_) {
                          setState(() => _metric = metric);
                          unawaited(_loadAnalytics());
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<_AnalyticsPeriod>(
                  initialValue: _period,
                  decoration: const InputDecoration(
                    labelText: 'Time period',
                    prefixIcon: Icon(Icons.date_range_rounded),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final period in _AnalyticsPeriod.values)
                      DropdownMenuItem(
                        value: period,
                        child: Text(period.label),
                      ),
                  ],
                  onChanged: (period) {
                    if (period == null) return;
                    setState(() => _period = period);
                    unawaited(_loadAnalytics());
                  },
                ),
                if (_period == _AnalyticsPeriod.custom) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        _RangeDateTile(
                          title: 'From',
                          value: _customStart,
                          onTap: () => _chooseCustomBound(isStart: true),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _RangeDateTile(
                          title: 'To',
                          value: _customEnd,
                          onTap: () => _chooseCustomBound(isStart: false),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_analytics case final analytics?)
                  _buildResults(analytics)
                else
                  const SizedBox.shrink(),
              ],
            ),
    );
  }

  Widget _buildResults(TaskAnalytics analytics) {
    if (analytics.sampleCount == 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 48),
        child: Text(
          'No ${_metricLabel(_metric).toLowerCase()} data in this period.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${analytics.sampleCount} ${analytics.sampleCount == 1 ? 'sample' : 'samples'}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _StatisticCard(label: 'Average', value: analytics.average),
            _StatisticCard(label: 'Median', value: analytics.median),
            _StatisticCard(label: 'Minimum', value: analytics.minimum),
            _StatisticCard(label: 'Maximum', value: analytics.maximum),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '${_metricLabel(_metric)} over time',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: DurationBarChart(
              buckets: analytics.buckets,
              bucketSize: _periodRange().bucketSize,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Bars show the average for each ${_bucketLabel(_periodRange().bucketSize)}.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _loadAnalytics() async {
    final name = _taskName;
    if (name == null) return;
    final request = ++_requestId;
    final range = _periodRange();
    setState(() {
      _isLoading = true;
      _analytics = null;
    });
    try {
      final result = await calculateTaskAnalytics(
        tasks: widget.viewModel.streamAnalyticsTasks(
          name,
          startedBefore: range.end,
        ),
        metric: _metric,
        bucketSize: range.bucketSize,
        startedAfter: range.start,
        startedBefore: range.end,
      );
      if (mounted && request == _requestId) {
        setState(() => _analytics = result);
      }
    } finally {
      if (mounted && request == _requestId) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _chooseCustomBound({required bool isStart}) async {
    final initial = isStart ? _customStart : _customEnd;
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (_) => DateTimeWheelPicker(
        initialDateTime: initial,
        title: isStart ? 'Analytics start' : 'Analytics end',
      ),
    );
    if (selected == null || !mounted) return;
    if (isStart && selected.isAfter(_customEnd)) {
      _showRangeError('The start of the range must be before its end.');
      return;
    }
    if (!isStart && selected.isBefore(_customStart)) {
      _showRangeError('The end of the range must be after its start.');
      return;
    }
    setState(() {
      if (isStart) {
        _customStart = selected;
      } else {
        _customEnd = selected;
      }
    });
    unawaited(_loadAnalytics());
  }

  ({DateTime? start, DateTime? end, AnalyticsBucketSize bucketSize})
  _periodRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _AnalyticsPeriod.day => (
        start: today,
        end: now,
        bucketSize: AnalyticsBucketSize.hour,
      ),
      _AnalyticsPeriod.week => (
        start: today.subtract(Duration(days: today.weekday - 1)),
        end: now,
        bucketSize: AnalyticsBucketSize.day,
      ),
      _AnalyticsPeriod.month => (
        start: DateTime(now.year, now.month),
        end: now,
        bucketSize: AnalyticsBucketSize.day,
      ),
      _AnalyticsPeriod.year => (
        start: DateTime(now.year),
        end: now,
        bucketSize: AnalyticsBucketSize.month,
      ),
      _AnalyticsPeriod.total => (
        start: null,
        end: null,
        bucketSize: AnalyticsBucketSize.year,
      ),
      _AnalyticsPeriod.custom => (
        start: _customStart,
        end: _customEnd,
        bucketSize: _customBucketSize(),
      ),
    };
  }

  AnalyticsBucketSize _customBucketSize() {
    final range = _customEnd.difference(_customStart);
    if (range <= const Duration(days: 2)) return AnalyticsBucketSize.hour;
    if (range <= const Duration(days: 62)) return AnalyticsBucketSize.day;
    if (range <= const Duration(days: 730)) return AnalyticsBucketSize.month;
    return AnalyticsBucketSize.year;
  }

  void _showRangeError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _StatisticCard extends StatelessWidget {
  const _StatisticCard({required this.label, required this.value});

  final String label;
  final Duration? value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value == null ? '—' : _formatDuration(value!),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _RangeDateTile extends StatelessWidget {
  const _RangeDateTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.calendar_today_outlined),
    title: Text(title),
    subtitle: Text(_formatDateTime(value)),
    trailing: const Icon(Icons.edit_calendar_outlined),
    onTap: onTap,
  );
}

String _metricLabel(AnalyticsMetric metric) => switch (metric) {
  AnalyticsMetric.taskDuration => 'Task duration',
  AnalyticsMetric.timeBetweenInstances => 'Time between instances',
};

String _bucketLabel(AnalyticsBucketSize size) => switch (size) {
  AnalyticsBucketSize.hour => 'hour',
  AnalyticsBucketSize.day => 'day',
  AnalyticsBucketSize.month => 'month',
  AnalyticsBucketSize.year => 'year',
};

String _formatDateTime(DateTime value) {
  final date =
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}

String _formatDuration(Duration duration) {
  final sign = duration.isNegative ? '−' : '';
  final absolute = duration.abs();
  if (absolute.inDays > 0) {
    return '$sign${absolute.inDays}d ${absolute.inHours.remainder(24)}h';
  }
  if (absolute.inHours > 0) {
    return '$sign${absolute.inHours}h ${absolute.inMinutes.remainder(60)}m';
  }
  if (absolute.inMinutes > 0) {
    return '$sign${absolute.inMinutes}m ${absolute.inSeconds.remainder(60)}s';
  }
  return '$sign${absolute.inSeconds}s';
}
