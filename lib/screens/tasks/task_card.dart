import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../models/task.dart';
import '../../utils/date_helper.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onDone;
  final VoidCallback? onDelete;

  const TaskCard({super.key, required this.task, required this.onDone, this.onDelete});

  Color _typeColor() {
    switch (task.type) {
      case 'reminder':  return AppColors.reminder;
      case 'recurring': return AppColors.recurring;
      case 'todo':      return AppColors.todo;
      default:          return AppColors.alarm;
    }
  }

  IconData _typeIcon() {
    switch (task.type) {
      case 'reminder':  return Icons.notifications_outlined;
      case 'recurring': return Icons.repeat;
      case 'todo':      return Icons.check_box_outline_blank;
      default:          return Icons.alarm_outlined;
    }
  }

  String _subtitle() {
    if (task.dueDate != null) return DateHelper.formatDisplay(task.dueDate);
    if (task.recurrence != null) return task.recurrence!;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor();
    final sub = _subtitle();
    final accent = Theme.of(context).colorScheme.primary;
    return Dismissible(
      key: Key('tc_${task.id}'),
      direction: onDelete != null
          ? DismissDirection.horizontal
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: AppColors.alarm.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: AppColors.alarm, size: 18),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: accent.withValues(alpha: 0.15),
        child: Icon(Icons.check, color: accent, size: 18),
      ),
      onDismissed: (direction) {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd && onDelete != null) {
          onDelete!();
        } else {
          onDone();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(left: BorderSide(color: color, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(sub,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
            Icon(_typeIcon(), color: color, size: 15),
          ],
        ),
      ),
    );
  }
}
