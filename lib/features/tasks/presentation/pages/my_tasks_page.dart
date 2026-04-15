import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../models/task_model.dart';
import '../../../../services/task_service.dart';

class MyTasksPage extends StatelessWidget {
  const MyTasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final taskService = context.read<TaskService>();
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'My Tasks',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
      ),
      body: StreamBuilder<List<Task>>(
        stream: taskService.getTasks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final tasks = snapshot.data ?? <Task>[];
          if (tasks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No tasks yet. Ask the voice coach to create one for you.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 16),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final progress = _progressFor(task);
              final nextStep = _nextStep(task);
              return Card(
                color: const Color(0xFF1E293B),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigoAccent.withOpacity(0.2),
                    child: Text(
                      '${(progress * 100).round()}%',
                      style: GoogleFonts.outfit(
                        color: Colors.indigoAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    task.title,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (nextStep != null)
                          Text(
                            'Next: $nextStep',
                            style: GoogleFonts.outfit(color: Colors.white70),
                          ),
                        if (task.reminderAt != null)
                          Text(
                            'Reminder: ${DateFormat.yMMMd().add_jm().format(task.reminderAt!)}',
                            style: GoogleFonts.outfit(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TaskDetailPage(taskId: task.id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  double _progressFor(Task task) {
    if (task.subTasks.isEmpty) {
      return task.isCompleted ? 1 : 0;
    }
    final completed = task.subTasks.where((s) => s.isCompleted).length;
    return completed / task.subTasks.length;
  }

  String? _nextStep(Task task) {
    for (final subTask in task.subTasks) {
      if (!subTask.isCompleted) {
        return subTask.title;
      }
    }
    return null;
  }
}

class TaskDetailPage extends StatelessWidget {
  final String taskId;

  const TaskDetailPage({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    final taskService = context.read<TaskService>();
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Task Details', style: GoogleFonts.outfit()),
      ),
      body: StreamBuilder<List<Task>>(
        stream: taskService.getTasks(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final task = snapshot.data!.where((t) => t.id == taskId).cast<Task?>().firstWhere(
                (t) => t != null,
                orElse: () => null,
              );
          if (task == null) {
            return Center(
              child: Text(
                'Task not found.',
                style: GoogleFonts.outfit(color: Colors.white70),
              ),
            );
          }

          final progress = _progressFor(task);
          final next = _nextStep(task);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                task.title,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                task.description.isEmpty ? 'No description yet.' : task.description,
                style: GoogleFonts.outfit(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.white12,
                color: Colors.indigoAccent,
              ),
              const SizedBox(height: 8),
              Text(
                'Completed ${(progress * 100).round()}%',
                style: GoogleFonts.outfit(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Text(
                'What to do next: ${next ?? 'All steps finished. Great work!'}',
                style: GoogleFonts.outfit(color: Colors.greenAccent),
              ),
              const SizedBox(height: 12),
              if (task.reminderAt != null)
                Text(
                  'Reminder set for ${DateFormat.yMMMd().add_jm().format(task.reminderAt!)}',
                  style: GoogleFonts.outfit(color: Colors.orangeAccent),
                ),
              if (task.sourcePrompt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Original request: ${task.sourcePrompt}',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Sub-tasks',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              ...task.subTasks.asMap().entries.map((entry) {
                final index = entry.key;
                final subTask = entry.value;
                return CheckboxListTile(
                  value: subTask.isCompleted,
                  activeColor: Colors.indigoAccent,
                  title: Text(
                    subTask.title,
                    style: GoogleFonts.outfit(color: Colors.white),
                  ),
                  onChanged: (value) async {
                    final updatedSubTasks = [...task.subTasks];
                    updatedSubTasks[index] = subTask.copyWith(
                      isCompleted: value ?? false,
                    );
                    final allDone = updatedSubTasks.isNotEmpty &&
                        updatedSubTasks.every((item) => item.isCompleted);
                    final updatedTask = task.copyWith(
                      subTasks: updatedSubTasks,
                      isCompleted: allDone,
                    );
                    await taskService.updateTask(updatedTask);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),
            ],
          );
        },
      ),
    );
  }

  double _progressFor(Task task) {
    if (task.subTasks.isEmpty) {
      return task.isCompleted ? 1 : 0;
    }
    final completed = task.subTasks.where((s) => s.isCompleted).length;
    return completed / task.subTasks.length;
  }

  String? _nextStep(Task task) {
    for (final subTask in task.subTasks) {
      if (!subTask.isCompleted) {
        return subTask.title;
      }
    }
    return null;
  }
}
