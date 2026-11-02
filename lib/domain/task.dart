import 'package:flutter/material.dart';

@immutable
class Task {
  const Task({
    required this.id,
    required this.name,
    required this.startedAt,
    this.endedAt,
    this.notes = '',
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String notes;

  bool get isRunning => endedAt == null;

  Duration durationAt(DateTime now) => (endedAt ?? now).difference(startedAt);

  Task copyWith({
    String? name,
    DateTime? startedAt,
    DateTime? endedAt,
    String? notes,
    bool clearEndedAt = false,
  }) => Task(
    id: id,
    name: name ?? this.name,
    startedAt: startedAt ?? this.startedAt,
    endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
    notes: notes ?? this.notes,
  );
}

const taskColors = <Color>[
  Color(0xFF5B8DEF),
  Color(0xFF28A889),
  Color(0xFFE59A35),
  Color(0xFFDA6577),
  Color(0xFF9670CC),
  Color(0xFF47A9B5),
  Color(0xFF73808F),
  Color(0xFFCB7D4B),
];

String taskColorKey(String name) => name.trim().toLowerCase();
