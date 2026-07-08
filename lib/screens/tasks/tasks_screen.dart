import 'package:flutter/material.dart';
import '../../core/db/database.dart';
import '../../core/db/repositories/task_repository.dart';
import '../../core/router/intent_router.dart';
import '../../core/theme/app_colors.dart';
import '../../models/intents/complete_intent.dart';
import '../../models/task.dart';
import '../../widget/widget_provider.dart';
import 'task_card.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, this.isVisible = false});
  final bool isVisible;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Task> _tasks = [];
  bool _loading = true;

  static const _order = ['alarm', 'recurring', 'reminder', 'todo'];
  static const _labels = {
    'alarm': 'ALARMS',
    'recurring': 'RECURRING',
    'reminder': 'REMINDERS',
    'todo': 'TODOS',
  };
  static const _colors = {
    'alarm': AppColors.alarm,
    'recurring': AppColors.recurring,
    'reminder': AppColors.reminder,
    'todo': AppColors.todo,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TasksScreen old) {
    super.didUpdateWidget(old);
    if (widget.isVisible && !old.isVisible) _load();
  }

  Future<void> _load() async {
    final db = await DatabaseHelper.instance.database;
    final tasks = await TaskRepository(db).getActive();
    if (mounted) setState(() { _tasks = tasks; _loading = false; });
  }

  Future<void> _markCompleteNow(Task task) async {
    final db = await DatabaseHelper.instance.database;
    if (task.id != null) await TaskRepository(db).markComplete(task.id!);
  }

  Future<void> _markActiveNow(Task task) async {
    final db = await DatabaseHelper.instance.database;
    if (task.id != null) await TaskRepository(db).markActive(task.id!);
  }

  Future<void> _cancelNotifications(Task task) async {
    final db = await DatabaseHelper.instance.database;
    await IntentRouter(db).route([CompleteIntent(searchTerm: task.title, scope: 'all')]);
    await WidgetProvider.refresh();
  }

  void _completeWithUndo(Task task) {
    final idx = _tasks.indexOf(task);
    setState(() => _tasks.remove(task));
    _markCompleteNow(task);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${task.title}" completed'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Theme.of(context).colorScheme.primary,
          onPressed: () {
            _markActiveNow(task);
            setState(() {
              if (idx >= 0 && idx <= _tasks.length) {
                _tasks.insert(idx, task);
              } else {
                _tasks.add(task);
              }
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    ).closed.then((reason) {
      if (reason != SnackBarClosedReason.action) {
        _cancelNotifications(task);
      }
    });
  }

  void _deleteWithUndo(Task task) {
    final idx = _tasks.indexOf(task);
    setState(() => _tasks.remove(task));
    _markCompleteNow(task);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${task.title}" deleted'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Theme.of(context).colorScheme.primary,
          onPressed: () {
            _markActiveNow(task);
            setState(() {
              if (idx >= 0 && idx <= _tasks.length) {
                _tasks.insert(idx, task);
              } else {
                _tasks.add(task);
              }
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    ).closed.then((reason) {
      if (reason != SnackBarClosedReason.action) {
        _cancelNotifications(task);
      }
    });
  }

  Map<String, List<Task>> _grouped() {
    final map = <String, List<Task>>{};
    for (final t in _tasks) {
      (map[t.type] ??= []).add(t);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          const Text('Tasks',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              )),
          const Spacer(),
          GestureDetector(
            onTap: _load,
            child: const Icon(Icons.refresh, color: AppColors.textSecondary, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    if (_tasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_box_outline_blank, size: 36, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('All clear.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    final grouped = _grouped();
    return RefreshIndicator(
      onRefresh: _load,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        children: [
          for (final type in _order)
            if (grouped.containsKey(type)) ...[
              _sectionHeader(
                _labels[type]!,
                _colors[type]!,
              ),
              for (final task in grouped[type]!)
                TaskCard(
                  task: task,
                  onDone: () => _completeWithUndo(task),
                  onDelete: () => _deleteWithUndo(task),
                ),
            ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Container(width: 6, height: 6, color: color),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.0,
              )),
        ],
      ),
    );
  }
}
