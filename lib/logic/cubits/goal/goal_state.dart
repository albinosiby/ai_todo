import 'package:equatable/equatable.dart';
import '../../../../data/models/goal_model.dart';
import '../../../../data/models/task_model.dart';

abstract class GoalState extends Equatable {
  const GoalState();

  @override
  List<Object?> get props => [];
}

class GoalInitial extends GoalState {}

class GoalLoading extends GoalState {}

class GoalLoaded extends GoalState {
  final List<GoalModel> goals;

  const GoalLoaded(this.goals);

  @override
  List<Object?> get props => [goals];
}

class GoalError extends GoalState {
  final String message;

  const GoalError(this.message);

  @override
  List<Object?> get props => [message];
}
