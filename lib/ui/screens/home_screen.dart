import 'package:flutter/material.dart';
import 'ai_chat_modal.dart';

import '../../data/models/todo_model.dart';
import '../../data/repositories/todo_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TodoRepository _todoRepository = TodoRepository();

  @override
  void initState() {
    super.initState();
  }

  void _showAIChatModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AIChatModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: StreamBuilder<List<TodoModel>>(
            stream: _todoRepository.watchTodos(),
            builder: (context, snapshot) {
              final todos = snapshot.data ?? const <TodoModel>[];
              final completed = todos.where((t) => t.isCompleted).length;
              final total = todos.length;
              final progress = total == 0 ? 0.0 : completed / total;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Today', style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            'Your todos',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 24),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            builder: (context) => Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Settings (coming soon)',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 8,
                                backgroundColor: colors.primary.withOpacity(0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                              ),
                              Center(
                                child: Text(
                                  '$completed/$total',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              )
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Progress', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text(
                                total == 0 ? 'Add your first todo with AI Coach.' : 'Keep going — you’ve got this.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Todos',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: todos.length,
                            itemBuilder: (context, index) {
                              final todo = todos[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: ListTile(
                                  leading: Checkbox(
                                    value: todo.isCompleted,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      _todoRepository.setCompleted(id: todo.id, isCompleted: val);
                                    },
                                    shape: const CircleBorder(),
                                    activeColor: colors.primary,
                                  ),
                                  title: Text(
                                    todo.title,
                                    style: TextStyle(
                                      decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                  subtitle: _TodoSubtitle(todo: todo),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAIChatModal,
        backgroundColor: colors.secondary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('AI Coach'),
      ),
    );
  }
}

class _TodoSubtitle extends StatelessWidget {
  final TodoModel todo;

  const _TodoSubtitle({required this.todo});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    final p = todo.priority?.trim();
    if (p != null && p.isNotEmpty) parts.add(p);
    final due = todo.dueAt;
    if (due != null) {
      final hh = due.hour.toString().padLeft(2, '0');
      final mm = due.minute.toString().padLeft(2, '0');
      parts.add('${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')} $hh:$mm');
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' • '));
  }
}
