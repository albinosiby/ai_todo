import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/repositories/goal_repository.dart';
import 'task_state.dart';

class TaskCubit extends Cubit<TaskState> {
  final GoalRepository _goalRepository;
  StreamSubscription? _taskSubscription;

  TaskCubit({required GoalRepository goalRepository})
      : _goalRepository = goalRepository,
        super(TaskInitial());

  void loadTasksForGoal(String goalId) {
    emit(TaskLoading());
    _taskSubscription?.cancel();
    _taskSubscription = _goalRepository.getTasksForGoal(goalId).listen(
      (tasks) {
        emit(TaskLoaded(tasks));
      },
      onError: (error) {
        emit(TaskError(error.toString()));
      },
    );
  }

  Future<void> toggleTaskCompletion(String goalId, String taskId, bool isCompleted) async {
    try {
      await _goalRepository.completeTask(goalId, taskId, isCompleted);
      // Confetti logic / Haptic logic will be handled at the UI layer upon listening to state updates
    } catch (e) {
      emit(TaskError(e.toString()));
    }
  }

  @override
  Future<void> close() {
    _taskSubscription?.cancel();
    return super.close();
  }
}
