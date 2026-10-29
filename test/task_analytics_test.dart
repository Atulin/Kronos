import 'package:flutter_test/flutter_test.dart';
import 'package:kronos/domain/task.dart';
import 'package:kronos/domain/task_analytics.dart';

void main() {
  test(
    'summarizes completed task durations and groups chart buckets',
    () async {
      final day = DateTime(2026, 10, 29);
      final tasks = [
        _task(
          'one',
          day.add(const Duration(hours: 9)),
          const Duration(minutes: 30),
        ),
        _task(
          'two',
          day.add(const Duration(hours: 10)),
          const Duration(minutes: 90),
        ),
        Task(
          id: 'running',
          name: 'Planning',
          startedAt: day.add(const Duration(hours: 12)),
        ),
      ];

      final analytics = await calculateTaskAnalytics(
        tasks: Stream.fromIterable(tasks),
        metric: AnalyticsMetric.taskDuration,
        bucketSize: AnalyticsBucketSize.hour,
      );

      expect(analytics.sampleCount, 2);
      expect(analytics.average, const Duration(hours: 1));
      expect(analytics.median, const Duration(hours: 1));
      expect(analytics.minimum, const Duration(minutes: 30));
      expect(analytics.maximum, const Duration(minutes: 90));
      expect(analytics.buckets, hasLength(2));
    },
  );

  test(
    'computes gaps using the previous task even when it precedes the range',
    () async {
      final day = DateTime(2026, 10, 29);
      final tasks = [
        _task(
          'one',
          day.add(const Duration(hours: 8)),
          const Duration(minutes: 15),
        ),
        _task(
          'two',
          day.add(const Duration(hours: 9)),
          const Duration(minutes: 30),
        ),
        _task(
          'three',
          day.add(const Duration(hours: 10, minutes: 15)),
          const Duration(minutes: 45),
        ),
        Task(
          id: 'running',
          name: 'Planning',
          startedAt: day.add(const Duration(hours: 12)),
        ),
      ];

      final analytics = await calculateTaskAnalytics(
        tasks: Stream.fromIterable(tasks),
        metric: AnalyticsMetric.timeBetweenInstances,
        bucketSize: AnalyticsBucketSize.hour,
        startedAfter: day.add(const Duration(hours: 9)),
        startedBefore: day.add(const Duration(hours: 12)),
      );

      expect(analytics.sampleCount, 3);
      expect(analytics.average, const Duration(minutes: 50));
      expect(analytics.median, const Duration(minutes: 45));
      expect(analytics.minimum, const Duration(minutes: 45));
      expect(analytics.maximum, const Duration(hours: 1));
    },
  );
}

Task _task(String id, DateTime start, Duration duration) => Task(
  id: id,
  name: 'Planning',
  startedAt: start,
  endedAt: start.add(duration),
);
