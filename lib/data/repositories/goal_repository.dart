import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/goal_model.dart';
import '../models/task_model.dart';

class GoalRepository {
  final FirebaseFirestore _firestore;

  GoalRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<GoalModel>> getGoals(String userId) {
    return _firestore
        .collection('goals')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => GoalModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> addGoalWithTasks(GoalModel goal, List<TaskModel> initialTasks) async {
    final batch = _firestore.batch();
    
    // Add goal
    final goalRef = _firestore.collection('goals').doc();
    final newGoal = goal.copyWith(id: goalRef.id);
    batch.set(goalRef, newGoal.toMap());

    // Add tasks under the goal
    for (var task in initialTasks) {
      final taskRef = goalRef.collection('tasks').doc();
      final newTask = task.copyWith(id: taskRef.id);
      batch.set(taskRef, newTask.toMap());
    }

    await batch.commit();
  }

  Stream<List<TaskModel>> getTasksForGoal(String goalId) {
    return _firestore
        .collection('goals')
        .doc(goalId)
        .collection('tasks')
        .orderBy('order')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => TaskModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> completeTask(String goalId, String taskId, bool isCompleted) async {
    await _firestore
        .collection('goals')
        .doc(goalId)
        .collection('tasks')
        .doc(taskId)
        .update({'isCompleted': isCompleted});
  }
}
