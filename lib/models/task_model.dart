import 'package:equatable/equatable.dart';

class Task extends Equatable {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime? reminderAt;
  final String sourcePrompt;
  final bool isCompleted;
  final List<SubTask> subTasks;

  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.reminderAt,
    this.sourcePrompt = '',
    this.isCompleted = false,
    this.subTasks = const [],
  });

  Task copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    String? sourcePrompt,
    bool? isCompleted,
    List<SubTask>? subTasks,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      reminderAt: clearReminderAt ? null : reminderAt ?? this.reminderAt,
      sourcePrompt: sourcePrompt ?? this.sourcePrompt,
      isCompleted: isCompleted ?? this.isCompleted,
      subTasks: subTasks ?? this.subTasks,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'reminderAt': reminderAt?.toIso8601String(),
      'sourcePrompt': sourcePrompt,
      'isCompleted': isCompleted,
      'subTasks': subTasks.map((x) => x.toMap()).toList(),
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    final dynamic createdAtRaw = map['createdAt'];
    final dynamic reminderAtRaw = map['reminderAt'];
    return Task(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      createdAt: _parseDateTime(createdAtRaw) ?? DateTime.now(),
      reminderAt: _parseDateTime(reminderAtRaw),
      sourcePrompt: map['sourcePrompt'] ?? '',
      isCompleted: map['isCompleted'] ?? false,
      subTasks: List<SubTask>.from(map['subTasks']?.map((x) => SubTask.fromMap(x)) ?? []),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    final dynamic milliseconds = value.millisecondsSinceEpoch;
    if (milliseconds is int) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        createdAt,
        reminderAt,
        sourcePrompt,
        isCompleted,
        subTasks,
      ];
}

class SubTask extends Equatable {
  final String id;
  final String title;
  final bool isCompleted;

  const SubTask({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  SubTask copyWith({
    String? id,
    String? title,
    bool? isCompleted,
  }) {
    return SubTask(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
    };
  }

  factory SubTask.fromMap(Map<String, dynamic> map) {
    return SubTask(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      isCompleted: map['isCompleted'] ?? false,
    );
  }

  @override
  List<Object?> get props => [id, title, isCompleted];
}
