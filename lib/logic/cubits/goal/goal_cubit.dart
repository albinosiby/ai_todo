import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../data/models/goal_model.dart';
import '../../../../data/repositories/goal_repository.dart';
import 'goal_state.dart';

class GoalCubit extends Cubit<GoalState> {
  final GoalRepository _goalRepository;
  StreamSubscription? _goalSubscription;

  GoalCubit({required GoalRepository goalRepository})
      : _goalRepository = goalRepository,
        super(GoalInitial());

  void loadGoals(String userId) {
    emit(GoalLoading());
    _goalSubscription?.cancel();
    _goalSubscription = _goalRepository.getGoals(userId).listen(
      (goals) {
        emit(GoalLoaded(goals));
      },
      onError: (error) {
        emit(GoalError(error.toString()));
      },
    );
  }

  @override
  Future<void> close() {
    _goalSubscription?.cancel();
    return super.close();
  }
}
