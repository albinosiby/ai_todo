import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/todo_model.dart';

class TodoRepository {
  final FirebaseFirestore _firestore;

  TodoRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<TodoModel>> watchTodos({int limit = 50}) {
    return _firestore
        .collection('todos')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
          toFirestore: (data, _) => data,
        )
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => TodoModel.fromDoc(d)).toList());
  }

  Future<String> createTodo({
    required String title,
    DateTime? dueAt,
    String? priority,
  }) async {
    final doc = await _firestore.collection('todos').add({
      'title': title,
      'isCompleted': false,
      'priority': priority,
      'dueAt': dueAt == null ? null : Timestamp.fromDate(dueAt),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> setCompleted({
    required String id,
    required bool isCompleted,
  }) {
    return _firestore.collection('todos').doc(id).update({'isCompleted': isCompleted});
  }
}

