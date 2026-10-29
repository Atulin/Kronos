import 'task.dart';

enum AnalyticsMetric { taskDuration, timeBetweenInstances }

enum AnalyticsBucketSize { hour, day, month, year }

class AnalyticsBucket {
  const AnalyticsBucket({
    required this.start,
    required this.average,
    required this.sampleCount,
  });

  final DateTime start;
  final Duration average;
  final int sampleCount;

  String label(AnalyticsBucketSize size) => switch (size) {
    AnalyticsBucketSize.hour => '${start.hour.toString().padLeft(2, '0')}:00',
    AnalyticsBucketSize.day => '${start.month}/${start.day}',
    AnalyticsBucketSize.month => _monthNames[start.month - 1],
    AnalyticsBucketSize.year => '${start.year}',
  };
}

class TaskAnalytics {
  const TaskAnalytics({
    required this.sampleCount,
    required this.average,
    required this.median,
    required this.minimum,
    required this.maximum,
    required this.buckets,
  });

  final int sampleCount;
  final Duration? average;
  final Duration? median;
  final Duration? minimum;
  final Duration? maximum;
  final List<AnalyticsBucket> buckets;
}

Future<TaskAnalytics> calculateTaskAnalytics({
  required Stream<Task> tasks,
  required AnalyticsMetric metric,
  required AnalyticsBucketSize bucketSize,
  DateTime? startedAfter,
  DateTime? startedBefore,
}) async {
  final values = <int>[];
  final bucketTotals = <DateTime, ({int total, int count})>{};
  Task? previous;

  bool isInRange(Task task) =>
      (startedAfter == null || !task.startedAt.isBefore(startedAfter)) &&
      (startedBefore == null || !task.startedAt.isAfter(startedBefore));

  void addValue(DateTime startedAt, Duration value) {
    final microseconds = value.inMicroseconds;
    values.add(microseconds);
    final bucket = _bucketStart(startedAt, bucketSize);
    final current = bucketTotals[bucket];
    bucketTotals[bucket] = (
      total: (current?.total ?? 0) + microseconds,
      count: (current?.count ?? 0) + 1,
    );
  }

  await for (final task in tasks) {
    if (metric == AnalyticsMetric.taskDuration) {
      if (!task.isRunning && isInRange(task)) {
        addValue(task.startedAt, task.durationAt(task.endedAt!));
      }
    } else {
      if (isInRange(task) && previous?.endedAt != null) {
        addValue(task.startedAt, task.startedAt.difference(previous!.endedAt!));
      }
      previous = task;
    }
  }

  if (values.isEmpty) {
    return const TaskAnalytics(
      sampleCount: 0,
      average: null,
      median: null,
      minimum: null,
      maximum: null,
      buckets: [],
    );
  }

  values.sort();
  final mid = values.length ~/ 2;
  final medianMicroseconds = values.length.isOdd
      ? values[mid]
      : (values[mid - 1] + values[mid]) ~/ 2;
  final buckets =
      bucketTotals.entries
          .map(
            (entry) => AnalyticsBucket(
              start: entry.key,
              average: Duration(
                microseconds: entry.value.total ~/ entry.value.count,
              ),
              sampleCount: entry.value.count,
            ),
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  return TaskAnalytics(
    sampleCount: values.length,
    average: Duration(
      microseconds: values.reduce((sum, value) => sum + value) ~/ values.length,
    ),
    median: Duration(microseconds: medianMicroseconds),
    minimum: Duration(microseconds: values.first),
    maximum: Duration(microseconds: values.last),
    buckets: List.unmodifiable(buckets),
  );
}

DateTime _bucketStart(DateTime value, AnalyticsBucketSize size) =>
    switch (size) {
      AnalyticsBucketSize.hour => DateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
      ),
      AnalyticsBucketSize.day => DateTime(value.year, value.month, value.day),
      AnalyticsBucketSize.month => DateTime(value.year, value.month),
      AnalyticsBucketSize.year => DateTime(value.year),
    };

const _monthNames = [
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
