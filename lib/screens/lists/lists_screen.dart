import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/db/database.dart';
import '../../core/db/repositories/list_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../models/task_list.dart';
import 'list_detail_screen.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key, this.isVisible = false});
  final bool isVisible;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  List<TaskList> _lists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ListsScreen old) {
    super.didUpdateWidget(old);
    if (widget.isVisible && !old.isVisible) _load();
  }

  Future<void> _load() async {
    final db = await DatabaseHelper.instance.database;
    final lists = await ListRepository(db).getLists();
    if (mounted) setState(() { _lists = lists; _loading = false; });
  }

  void _deleteWithUndo(TaskList list) {
    final idx = _lists.indexOf(list);
    setState(() => _lists.remove(list));
    HapticFeedback.mediumImpact();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${list.name}" deleted'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Theme.of(context).colorScheme.primary,
          onPressed: () {
            setState(() {
              if (idx >= 0 && idx <= _lists.length) {
                _lists.insert(idx, list);
              } else {
                _lists.add(list);
              }
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    ).closed.then((reason) {
      if (reason != SnackBarClosedReason.action) {
        _doDelete(list);
      }
    });
  }

  Future<void> _doDelete(TaskList list) async {
    final db = await DatabaseHelper.instance.database;
    await ListRepository(db).deleteList(list.id!);
  }

  IconData _icon(String category) {
    switch (category) {
      case 'movies': return Icons.movie_outlined;
      case 'anime':  return Icons.tv_outlined;
      case 'shows':  return Icons.live_tv_outlined;
      case 'books':  return Icons.menu_book_outlined;
      default:       return Icons.list_outlined;
    }
  }

  Color _color(String category) {
    switch (category) {
      case 'movies': return AppColors.alarm;
      case 'anime':  return AppColors.reminder;
      case 'shows':  return AppColors.reminder;
      case 'books':  return AppColors.recurring;
      default:       return AppColors.todo;
    }
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
          const Text('Lists',
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
    if (_lists.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.list_outlined, size: 36, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('No lists yet.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            SizedBox(height: 4),
            Text('"add Inception to my movies list"',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: AppColors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = (constraints.maxWidth / 180).floor().clamp(2, 4);
          return GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.1,
        ),
        itemCount: _lists.length,
        itemBuilder: (ctx, i) {
          final list = _lists[i];
          final color = _color(list.category);
          return GestureDetector(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ListDetailScreen(list: list)),
              );
              _load();
            },
            onLongPress: () => _deleteWithUndo(list),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: color, width: 2)),
              ),
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icon(list.category), color: color, size: 20),
                  const SizedBox(height: 8),
                  Text(list.name,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(list.category,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
          );
        },
      );
        },
      ),
    );
  }
}
