import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/db/database.dart';
import '../../core/db/repositories/list_repository.dart';
import '../../core/scheduler/alarm_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/task_list.dart';
import '../../models/list_item.dart';

/// Daily Non-Negotiables — three fixed sections (Intellectual / Physical /
/// Spiritual). Each holds items the user adds/removes, resets its checkboxes
/// every morning, and fires a daily reminder at a per-section time.
class NonNegotiablesScreen extends StatefulWidget {
  const NonNegotiablesScreen({super.key, this.isVisible = false});
  final bool isVisible;

  @override
  State<NonNegotiablesScreen> createState() => _NonNegotiablesScreenState();
}

class _NonNegotiablesScreenState extends State<NonNegotiablesScreen> {
  // slug -> (icon, accent colour, default 'HH:MM')
  static const _meta = <String, (IconData, Color, String)>{
    'intellectual': (Icons.psychology_outlined, AppColors.reminder, '09:00'),
    'physical': (Icons.fitness_center_outlined, AppColors.todo, '18:00'),
    'spiritual': (Icons.self_improvement_outlined, AppColors.recurring, '21:00'),
  };

  List<TaskList> _sections = [];
  final Map<int, List<ListItem>> _items = {};
  final Map<String, String> _times = {}; // slug -> 'HH:MM'
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NonNegotiablesScreen old) {
    super.didUpdateWidget(old);
    if (widget.isVisible && !old.isVisible) _load();
  }

  String _slugFor(TaskList s) =>
      ListRepository.nonNegotiableSections
          .firstWhere((e) => e.$2 == s.name, orElse: () => ('', s.name, ''))
          .$1;

  Future<void> _load() async {
    final db = await DatabaseHelper.instance.database;
    final repo = ListRepository(db);

    await _resetIfNewDay(repo);

    final sections = await repo.ensureNonNegotiableSections();
    final alarm = AlarmService();
    _items.clear();
    for (final s in sections) {
      _items[s.id!] = await repo.getItems(s.id!);
      final slug = _slugFor(s);
      // First run for this section → arm its default reminder.
      var time = await alarm.nonNegotiableTime(slug);
      if (time == null) {
        time = _meta[slug]?.$3 ?? '09:00';
        await alarm.scheduleNonNegotiableReminder(
            slug: slug, name: s.name, time: time);
      }
      _times[slug] = time;
    }

    if (mounted) setState(() { _sections = sections; _loading = false; });
  }

  /// Clear every section's checkboxes once per calendar day.
  Future<void> _resetIfNewDay(ListRepository repo) async {
    final today = DateTime.now();
    final key = '${today.year}-${today.month}-${today.day}';
    final sp = await SharedPreferences.getInstance();
    if (sp.getString('nn_reset_date') != key) {
      await repo.resetNonNegotiableDone();
      await sp.setString('nn_reset_date', key);
    }
  }

  // ---- item mutations ----

  Future<void> _addItem(TaskList section) async {
    final text = await _promptText('Add to ${section.name}', 'e.g. Read 20 pages');
    if (text == null || text.trim().isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final repo = ListRepository(db);
    await repo.insertItem(ListItem(listId: section.id!, title: text.trim()));
    HapticFeedback.lightImpact();
    _items[section.id!] = await repo.getItems(section.id!);
    if (mounted) setState(() {});
  }

  Future<void> _toggleDone(TaskList section, ListItem item) async {
    final db = await DatabaseHelper.instance.database;
    final repo = ListRepository(db);
    await repo.setItemDone(item.id!, !item.isDone);
    HapticFeedback.selectionClick();
    _items[section.id!] = await repo.getItems(section.id!);
    if (mounted) setState(() {});
  }

  Future<void> _deleteItem(TaskList section, ListItem item) async {
    final db = await DatabaseHelper.instance.database;
    final repo = ListRepository(db);
    setState(() => _items[section.id!]!.remove(item));
    HapticFeedback.mediumImpact();
    await repo.deleteItem(item.id!);

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${item.title}" removed'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Theme.of(context).colorScheme.primary,
          onPressed: () async {
            await repo.insertItem(ListItem(
                listId: item.listId, title: item.title, isDone: item.isDone));
            _items[section.id!] = await repo.getItems(section.id!);
            if (mounted) setState(() {});
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _editTime(TaskList section) async {
    final slug = _slugFor(section);
    final current = _times[slug] ?? '09:00';
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: Theme.of(ctx).colorScheme.primary,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final time =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    await AlarmService().scheduleNonNegotiableReminder(
        slug: slug, name: section.name, time: time);
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _times[slug] = time);
  }

  Future<String?> _promptText(String title, String hint) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          cursorColor: Theme.of(ctx).colorScheme.primary,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.divider)),
            focusedBorder: UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Theme.of(ctx).colorScheme.primary)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text('Add',
                  style:
                      TextStyle(color: Theme.of(ctx).colorScheme.primary))),
        ],
      ),
    );
  }

  String _pretty(String hhmm) {
    final p = hhmm.split(':');
    final t = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
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
        children: const [
          Text('Daily Non-Negotiables',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              )),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [for (final s in _sections) _sectionCard(s)],
      ),
    );
  }

  Widget _sectionCard(TaskList section) {
    final slug = _slugFor(section);
    final (icon, color, _) = _meta[slug] ?? (Icons.circle_outlined, AppColors.accent, '09:00');
    final items = _items[section.id!] ?? const [];
    final time = _times[slug];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: color, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Text(section.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _editTime(section),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_none,
                          size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(time == null ? '--' : _pretty(time),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _addItem(section),
                  icon: Icon(Icons.add, size: 20, color: color),
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 2, 14, 16),
              child: Text('Nothing here yet — tap + to add one.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            )
          else
            ...items.map((it) => _itemRow(section, it, color)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _itemRow(TaskList section, ListItem item, Color color) {
    return Dismissible(
      key: Key('nn_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.alarm.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: AppColors.alarm, size: 16),
      ),
      onDismissed: (_) => _deleteItem(section, item),
      child: InkWell(
        onTap: () => _toggleDone(section, item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
          child: Row(
            children: [
              Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: item.isDone ? color : Colors.transparent,
                  border: Border.all(
                    color: item.isDone ? color : AppColors.textSecondary,
                    width: 1.5,
                  ),
                ),
                child: item.isDone
                    ? Icon(Icons.check, size: 10, color: AppColors.accentFg)
                    : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(item.title,
                    style: TextStyle(
                      fontSize: 14,
                      color: item.isDone
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      decoration:
                          item.isDone ? TextDecoration.lineThrough : null,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
