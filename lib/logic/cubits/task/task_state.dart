import 'package:equatable/equatable.dart';
import '../../../../data/models/task_model.dart';

abstract class TaskState extends Equatable {
  const TaskState();

  @override
  List<Object?> get props => [];
}

class TaskInitial extends TaskState {}

class TaskLoading extends TaskState {}

class TaskLoaded extends TaskState {
  final List<TaskModel> tasks;
  
  // Expose the "Daily 3" tasks separated out.
  List<TaskModel> get daily3 {
    final uncompleted = tasks.where((t) => !t.isCompleted).toList();
    // Example logic: prioritize by priority ('high' first) and dueAt.
    uncompleted.sort((a, b) {
      if (a.priority == b.priority) {
        return a.dueAt.compareTo(b.dueAt);
      }
      // Simple custom arbitrary weight for priority
      final map = {'high': 1, 'medium': 2, 'low': 3};
      return (map[a.priority] ?? 2).compareTo(map[b.priority] ?? 2);
    });
    return uncompleted.take(3).toList();
  }

  const TaskLoaded(this.tasks);

  @override
  List<Object?> get props => [tasks];
}

class TaskError extends TaskState {
  final String message;

  const TaskError(this.message);

  @override
  List<Object?> get props => [message];
}
