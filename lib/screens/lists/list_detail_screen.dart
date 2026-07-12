import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/db/database.dart';
import '../../core/db/repositories/list_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../models/task_list.dart';
import '../../models/list_item.dart';

class ListDetailScreen extends StatefulWidget {
  final TaskList list;
  const ListDetailScreen({super.key, required this.list});

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  List<ListItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseHelper.instance.database;
    final items = await ListRepository(db).getItems(widget.list.id!);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _markDoneInDb(int id) async {
    final db = await DatabaseHelper.instance.database;
    await ListRepository(db).markItemDone(id);
  }

  Future<void> _markUndoneInDb(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('list_items', {'is_done': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _deleteInDb(int id) async {
    final db = await DatabaseHelper.instance.database;
    await ListRepository(db).deleteItem(id);
  }

  Future<void> _reinsertInDb(ListItem item) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('list_items', item.toMap());
  }

  void _toggleDoneWithUndo(ListItem item) {
    if (item.isDone) return;
    final idx = _items.indexOf(item);
    final updated = ListItem(
      id: item.id,
      listId: item.listId,
      title: item.title,
      notes: item.notes,
      isDone: true,
    );
    setState(() => _items[idx] = updated);
    HapticFeedback.lightImpact();
    _markDoneInDb(item.id!);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${item.title}" marked done'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Theme.of(context).colorScheme.primary,
          onPressed: () {
            _markUndoneInDb(item.id!);
            setState(() => _items[idx] = item);
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _deleteWithUndo(ListItem item) {
    final idx = _items.indexOf(item);
    setState(() => _items.remove(item));
    HapticFeedback.mediumImpact();
    _deleteInDb(item.id!);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${item.title}" deleted'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Theme.of(context).colorScheme.primary,
          onPressed: () {
            _reinsertInDb(item);
            setState(() {
              if (idx >= 0 && idx <= _items.length) {
                _items.insert(idx, item);
              } else {
                _items.add(item);
              }
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteList() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete list?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('This will delete "${widget.list.name}" and all its items.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.alarm)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final db = await DatabaseHelper.instance.database;
      await ListRepository(db).deleteList(widget.list.id!);
      if (mounted) Navigator.pop(context);
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
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: AppColors.textSecondary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(widget.list.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                )),
          ),
          GestureDetector(
            onTap: _deleteList,
            child: const Icon(Icons.delete_outline, color: AppColors.textSecondary, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      return const Center(
        child: Text('Nothing here yet.\nTell the chat to add items!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      itemCount: _items.length,
      separatorBuilder: (_, _) =>
          const Divider(color: AppColors.divider, height: 1),
      itemBuilder: (ctx, i) => _itemRow(_items[i]),
    );
  }

  Widget _itemRow(ListItem item) {
    final accent = Theme.of(context).colorScheme.primary;
    return Dismissible(
      key: Key('li_${item.id}'),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        color: accent.withValues(alpha: 0.15),
        child: Icon(Icons.check, color: accent, size: 16),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.alarm.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: AppColors.alarm, size: 16),
      ),
      onDismissed: (direction) {
        if (direction == DismissDirection.startToEnd) {
          _toggleDoneWithUndo(item);
        } else {
          _deleteWithUndo(item);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _toggleDoneWithUndo(item),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: item.isDone ? accent : Colors.transparent,
                  border: Border.all(
                    color: item.isDone ? accent : AppColors.textSecondary,
                    width: 1.5,
                  ),
                ),
                child: item.isDone
                    ? Icon(Icons.check, size: 9, color: AppColors.accentFg)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(item.title,
                  style: TextStyle(
                    fontSize: 14,
                    color: item.isDone ? AppColors.textSecondary : AppColors.textPrimary,
                    decoration: item.isDone ? TextDecoration.lineThrough : null,
                  )),
            ),
            if (item.notes != null)
              Flexible(
                flex: 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(item.notes!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
