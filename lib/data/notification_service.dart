import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/task.dart';
import '../domain/task_reminder.dart';

/// Stable notification id for a running task's reminder.
int reminderNotificationId(String taskId) => taskId.hashCode & 0x7FFFFFFF;

/// Schedules and cancels the notifications backing task reminders.
abstract interface class ReminderNotifier {
  /// Arms the reminder for a running task, replacing any previous schedule.
  Future<void> scheduleRunningTask(Task task, TaskReminder reminder);

  /// Removes the reminder of a running task, pending or already shown.
  Future<void> cancelRunningTask(Task task);

  /// Clears every pending reminder; used when re-syncing, typically on load.
  Future<void> cancelAllPending();

  /// Asks the user for permission to show notifications.
  Future<void> requestPermissions();

  /// Immediately shows an example notification with the reminder's sound.
  Future<void> showPreview(TaskReminder reminder);
}

class NoopReminderNotifier implements ReminderNotifier {
  const NoopReminderNotifier();

  @override
  Future<void> scheduleRunningTask(Task task, TaskReminder reminder) async {}

  @override
  Future<void> cancelRunningTask(Task task) async {}

  @override
  Future<void> cancelAllPending() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> showPreview(TaskReminder reminder) async {}
}

class LocalReminderNotifier implements ReminderNotifier {
  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  Future<FlutterLocalNotificationsPlugin> _ensureInitialized() async {
    if (!_initialized) {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
      final plugin = _plugin ??= FlutterLocalNotificationsPlugin();
      // The launcher icon doubles as the small icon on Android.
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher'),
        ),
      );
      _initialized = true;
    }
    return _plugin!;
  }

  /// Exact alarms are pre-granted on Android 12, but on newer versions users
  /// must allow them; fall back to inexact alarms when unavailable.
  Future<AndroidScheduleMode> _scheduleMode(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    try {
      final canScheduleExact = await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.canScheduleExactNotifications();
      if (canScheduleExact ?? true) {
        return AndroidScheduleMode.exactAllowWhileIdle;
      }
    } catch (error) {
      debugPrint('Exact-alarm check failed, scheduling inexact: $error');
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  AndroidNotificationDetails _details(TaskReminder reminder) {
    final sound = reminderSoundFor(reminder.sound);
    final resource = sound.resource;
    return AndroidNotificationDetails(
      resource == null ? 'kronos_reminder' : 'kronos_reminder_${sound.key}',
      'Task timers',
      channelDescription:
          'Reminders fired while a timed task is running, with the chosen sound.',
      ticker: 'Task timer',
      importance: Importance.max,
      priority: Priority.high,
      sound: resource == null
          ? null
          : RawResourceAndroidNotificationSound(resource),
    );
  }

  @override
  Future<void> scheduleRunningTask(Task task, TaskReminder reminder) async {
    final body =
        '“${task.name}” has been running for '
        '${_intervalLabel(reminder.interval)}.';
    try {
      final plugin = await _ensureInitialized();
      final id = reminderNotificationId(task.id);
      final details = NotificationDetails(android: _details(reminder));
      final scheduleMode = await _scheduleMode(plugin);
      await plugin.cancel(id: id);
      if (reminder.repeats) {
        await plugin.periodicallyShowWithDuration(
          id: id,
          title: task.name,
          body: body,
          repeatDurationInterval: reminder.interval,
          notificationDetails: details,
          androidScheduleMode: scheduleMode,
        );
      } else {
        final scheduledAt = tz.TZDateTime.from(
          task.startedAt,
          tz.local,
        ).add(reminder.interval);
        // A one-time reminder whose window already elapsed has nothing left
        // to remind about.
        if (!scheduledAt.isAfter(tz.TZDateTime.now(tz.local))) return;
        await plugin.zonedSchedule(
          id: id,
          title: task.name,
          body: body,
          scheduledDate: scheduledAt,
          notificationDetails: details,
          androidScheduleMode: scheduleMode,
        );
      }
    } catch (error) {
      // Scheduling needs the Android platform; when it is missing (unit
      // tests, non-Android host) remembering the reminder is still enough.
      debugPrint('Task reminder scheduling failed: $error');
    }
  }

  @override
  Future<void> cancelRunningTask(Task task) async {
    try {
      final plugin = await _ensureInitialized();
      await plugin.cancel(id: reminderNotificationId(task.id));
    } catch (error) {
      debugPrint('Task reminder cancellation failed: $error');
    }
  }

  @override
  Future<void> cancelAllPending() async {
    try {
      final plugin = await _ensureInitialized();
      await plugin.cancelAllPendingNotifications();
    } catch (error) {
      debugPrint('Task reminder reset failed: $error');
    }
  }

  @override
  Future<void> requestPermissions() async {
    try {
      final plugin = await _ensureInitialized();
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('Task reminder permission request failed: $error');
    }
  }

  @override
  Future<void> showPreview(TaskReminder reminder) async {
    const body = 'Example of the sound this reminder will play.';
    try {
      final plugin = await _ensureInitialized();
      await plugin.show(
        id: 1,
        title: 'Task timer',
        body: body,
        notificationDetails: NotificationDetails(android: _details(reminder)),
      );
    } catch (error) {
      debugPrint('Task reminder preview failed: $error');
    }
  }

  static String _intervalLabel(Duration interval) {
    final totalMinutes = interval.inMinutes;
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0
        ? '$hours h'
        : '$hours h ${minutes.toString().padLeft(2, '0')} min';
  }
}
