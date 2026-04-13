import 'package:equatable/equatable.dart';

class DailyStatsModel extends Equatable {
  final String id;
  final String userId;
  final DateTime date;
  final int tasksCompleted;

  const DailyStatsModel({
    required this.id,
    required this.userId,
    required this.date,
    this.tasksCompleted = 0,
  });

  factory DailyStatsModel.fromMap(Map<String, dynamic> map, String documentId) {
    return DailyStatsModel(
      id: documentId,
      userId: map['userId'] ?? '',
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] ?? 0),
      tasksCompleted: map['tasksCompleted']?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'date': date.millisecondsSinceEpoch,
      'tasksCompleted': tasksCompleted,
    };
  }

  DailyStatsModel copyWith({
    String? id,
    String? userId,
    DateTime? date,
    int? tasksCompleted,
  }) {
    return DailyStatsModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      tasksCompleted: tasksCompleted ?? this.tasksCompleted,
    );
  }

  @override
  List<Object> get props => [id, userId, date, tasksCompleted];
}
