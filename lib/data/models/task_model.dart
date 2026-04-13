import 'package:equatable/equatable.dart';

class TaskModel extends Equatable {
  final String id;
  final String title;
  final String priority; // 'high', 'medium', 'low' based on Eisenhower Matrix approx.
  final DateTime dueAt;
  final bool isCompleted;
  final int order;

  const TaskModel({
    required this.id,
    required this.title,
    required this.priority,
    required this.dueAt,
    this.isCompleted = false,
    required this.order,
  });

  factory TaskModel.fromMap(Map<String, dynamic> map, String documentId) {
    return TaskModel(
      id: documentId,
      title: map['title'] ?? '',
      priority: map['priority'] ?? 'medium',
      dueAt: DateTime.fromMillisecondsSinceEpoch(map['dueAt'] ?? 0),
      isCompleted: map['isCompleted'] ?? false,
      order: map['order']?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'priority': priority,
      'dueAt': dueAt.millisecondsSinceEpoch,
      'isCompleted': isCompleted,
      'order': order,
    };
  }

  TaskModel copyWith({
    String? id,
    String? title,
    String? priority,
    DateTime? dueAt,
    bool? isCompleted,
    int? order,
  }) {
    return TaskModel(
      id: id ?? this.id,
      title: title ?? this.title,
      priority: priority ?? this.priority,
      dueAt: dueAt ?? this.dueAt,
      isCompleted: isCompleted ?? this.isCompleted,
      order: order ?? this.order,
    );
  }

  @override
  List<Object> get props => [id, title, priority, dueAt, isCompleted, order];
}
