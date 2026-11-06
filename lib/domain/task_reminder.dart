import 'package:flutter/material.dart';

/// Sound options for task reminders.
///
/// `resource` refers to a WAV file in `android/app/src/main/res/raw`; for the
/// system default it is null and the device's notification sound plays.
@immutable
class ReminderSound {
  const ReminderSound(this.key, this.label, this.resource);

  final String key;
  final String label;
  final String? resource;
}

const defaultReminderSound = 'default';

const reminderSounds = <ReminderSound>[
  ReminderSound('default', 'System default', null),
  ReminderSound('bell', 'Bell', 'kronos_bell'),
  ReminderSound('chime', 'Chime', 'kronos_chime'),
  ReminderSound('ping', 'Ping', 'kronos_ping'),
  ReminderSound('sweep', 'Sweep', 'kronos_sweep'),
];

ReminderSound reminderSoundFor(String key) => reminderSounds.firstWhere(
  (sound) => sound.key == key,
  orElse: () => reminderSounds.first,
);

/// Timer settings shared by every task named alike.
///
/// Stored separately from tasks, keyed by [taskColorKey], in the same way as
/// task colors. When a task with this reminder runs, a notification with a
/// customizable sound fires after [interval] (and again every [interval] when
/// [repeats] is true until the task is stopped).
@immutable
class TaskReminder {
  const TaskReminder({
    required this.interval,
    this.repeats = false,
    this.sound = defaultReminderSound,
  });

  final Duration interval;
  final bool repeats;

  /// Key of an entry in [reminderSounds].
  final String sound;

  int get minutes => interval.inMinutes;

  TaskReminder copyWith({Duration? interval, bool? repeats, String? sound}) =>
      TaskReminder(
        interval: interval ?? this.interval,
        repeats: repeats ?? this.repeats,
        sound: sound ?? this.sound,
      );

  @override
  bool operator ==(Object other) =>
      other is TaskReminder &&
      other.interval == interval &&
      other.repeats == repeats &&
      other.sound == sound;

  @override
  int get hashCode => Object.hash(interval, repeats, sound);
}
