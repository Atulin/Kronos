import 'package:flutter/foundation.dart';

@immutable
class TaskFilter {
  const TaskFilter({this.query = '', this.startedAfter, this.startedBefore});

  final String query;
  final DateTime? startedAfter;
  final DateTime? startedBefore;

  bool get isActive =>
      query.trim().isNotEmpty || startedAfter != null || startedBefore != null;

  @override
  bool operator ==(Object other) =>
      other is TaskFilter &&
      other.query == query &&
      other.startedAfter == startedAfter &&
      other.startedBefore == startedBefore;

  @override
  int get hashCode => Object.hash(query, startedAfter, startedBefore);
}
