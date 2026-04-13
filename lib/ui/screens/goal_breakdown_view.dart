import 'package:flutter/material.dart';
import '../../data/models/task_model.dart';

class GoalBreakdownView extends StatefulWidget {
  final String goalTitle;
  final List<TaskModel> initialTasks;

  const GoalBreakdownView({
    Key? key,
    required this.goalTitle,
    required this.initialTasks,
  }) : super(key: key);

  @override
  State<GoalBreakdownView> createState() => _GoalBreakdownViewState();
}

class _GoalBreakdownViewState extends State<GoalBreakdownView> {
  // Normally this state would be managed by GoalCubit or TaskCubit
  late List<TaskModel> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = List.from(widget.initialTasks);
  }

  void _toggleTask(int index) {
    setState(() {
      _tasks[index] = _tasks[index].copyWith(
        isCompleted: !_tasks[index].isCompleted,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goal Breakdown'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              // Navigate to analytics
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.goalTitle,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 8),
            Text(
              'Here is the step-by-step plan AI generated for you.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: _tasks.length,
                itemBuilder: (context, index) {
                  final task = _tasks[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: task.isCompleted ? 0 : 2,
                    color: task.isCompleted
                        ? Theme.of(context).colorScheme.surface.withOpacity(0.5)
                        : Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      onTap: () => _toggleTask(index),
                      leading: Checkbox(
                        value: task.isCompleted,
                        onChanged: (val) => _toggleTask(index),
                        shape: const CircleBorder(),
                        activeColor: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        task.title,
                        style: TextStyle(
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          color: task.isCompleted ? Colors.grey : null,
                        ),
                      ),
                      subtitle: Text(task.priority.toUpperCase()),
                      trailing: Icon(
                        Icons.drag_indicator,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  // Finalize logic, push back to dashboard
                  Navigator.of(context).pop();
                },
                child: const Text('Commit to Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
