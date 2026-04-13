import 'package:cloud_firestore/cloud_firestore.dart';

class TodoModel {
  final String id;
  final String title;
  final bool isCompleted;
  final String? priority;
  final DateTime? dueAt;
  final DateTime? createdAt;

  const TodoModel({
    required this.id,
    required this.title,
    required this.isCompleted,
    this.priority,
    this.dueAt,
    this.createdAt,
  });

  factory TodoModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      return TodoModel(
        id: doc.id,
        title: '',
        isCompleted: false,
      );
    }
    return TodoModel(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      isCompleted: (data['isCompleted'] as bool?) ?? false,
      priority: data['priority'] as String?,
      dueAt: (data['dueAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

