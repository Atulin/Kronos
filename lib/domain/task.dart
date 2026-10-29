import 'package:flutter/material.dart';

@immutable
class Task {
  const Task({
    required this.id,
    required this.name,
    required this.startedAt,
    this.endedAt,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isRunning => endedAt == null;

  Duration durationAt(DateTime now) => (endedAt ?? now).difference(startedAt);

  Task copyWith({
    String? name,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
  }) => Task(
    id: id,
    name: name ?? this.name,
    startedAt: startedAt ?? this.startedAt,
    endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
  };

  factory Task.fromJson(Map<String, Object?> json) => Task(
    id: json['id']! as String,
    name: json['name']! as String,
    startedAt: DateTime.parse(json['startedAt']! as String),
    endedAt: json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt']! as String),
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
