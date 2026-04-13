import 'package:equatable/equatable.dart';

class GoalModel extends Equatable {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String category;
  final DateTime targetDate;
  final bool isCompleted;

  const GoalModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.category,
    required this.targetDate,
    this.isCompleted = false,
  });

  factory GoalModel.fromMap(Map<String, dynamic> map, String documentId) {
    return GoalModel(
      id: documentId,
      userId: map['userId'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: map['category'] ?? '',
      targetDate: DateTime.fromMillisecondsSinceEpoch(map['targetDate'] ?? 0),
      isCompleted: map['isCompleted'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'description': description,
      'category': category,
      'targetDate': targetDate.millisecondsSinceEpoch,
      'isCompleted': isCompleted,
    };
  }

  GoalModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    String? category,
    DateTime? targetDate,
    bool? isCompleted,
  }) {
    return GoalModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      targetDate: targetDate ?? this.targetDate,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  @override
  List<Object> get props => [
        id,
        userId,
        title,
        description,
        category,
        targetDate,
        isCompleted,
      ];
}
