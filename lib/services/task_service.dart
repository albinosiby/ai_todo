import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _logTag = 'TaskService';

  Future<void> saveTask(Task task) async {
    developer.log('Saving task id=${task.id}, title="${task.title}"', name: _logTag);
    await _firestore.collection('tasks').doc(task.id).set(task.toMap());
    developer.log('Task saved id=${task.id}', name: _logTag);
  }

  Stream<List<Task>> getTasks() {
    return _firestore.collection('tasks').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Task.fromMap(doc.data())).toList();
    }).map((tasks) {
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return tasks;
    });
  }

  Future<void> updateTask(Task task) async {
    developer.log('Updating task id=${task.id}', name: _logTag);
    await _firestore.collection('tasks').doc(task.id).update(task.toMap());
  }

  Future<void> deleteTask(String id) async {
    developer.log('Deleting task id=$id', name: _logTag);
    await _firestore.collection('tasks').doc(id).delete();
  }
}
