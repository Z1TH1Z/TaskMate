import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/db/database.dart';
import '../../core/db/repositories/alarm_repository.dart';
import '../../core/scheduler/alarm_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/alarm_model.dart';
import '../../utils/date_helper.dart';
import '../../widget/widget_provider.dart';

class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key, this.isVisible = false});
  final bool isVisible;

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen> {
  List<AlarmModel> _alarms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AlarmsScreen old) {
    super.didUpdateWidget(old);
    if (widget.isVisible && !old.isVisible) _load();
  }

  Future<void> _load() async {
    await AlarmService().reconcileFiredAlarms();
    final db = await DatabaseHelper.instance.database;
    final alarms = await AlarmRepository(db).getActiveAlarms();
    alarms.sort((a, b) => _nextFire(a).compareTo(_nextFire(b)));
    if (mounted) setState(() { _alarms = alarms; _loading = false; });
  }

  DateTime _nextFire(AlarmModel a) {
    final now = DateTime.now();
    final p = a.alarmTime.split(':');
    var dt = DateTime(now.year, now.month, now.day,
        int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0);
    if (!dt.isAfter(now)) dt = dt.add(const Duration(days: 1));
    if (a.recurrence == 'weekdays') {
      while (dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday) {
        dt = dt.add(const Duration(days: 1));
      }
    }
    return dt;
  }

  String _whenLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes}m';
    if (dt.day == now.day) {
      return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final dayLabel = (dt.year == tomorrow.year &&
            dt.month == tomorrow.month &&
            dt.day == tomorrow.day)
        ? 'Tomorrow'
        : DateFormat('EEE').format(dt);
    return '$dayLabel, ${DateFormat('h:mm a').format(dt)}';
  }

  String _recurrenceLabel(String r) {
    switch (r) {
      case 'daily':
        return 'Daily';
      case 'weekdays':
        return 'Weekdays';
      default:
        return 'Once';
    }
  }

  Future<void> _deactivateNow(AlarmModel a) async {
    final db = await DatabaseHelper.instance.database;
    if (a.id != null) await AlarmRepository(db).deactivateById(a.id!);
  }

  Future<void> _reactivateNow(AlarmModel a) async {
    final db = await DatabaseHelper.instance.database;
    if (a.id != null) {
      await db.update('alarms', {'is_active': 1},
          where: 'id = ?', whereArgs: [a.id]);
    }
  }

  void _cancelWithUndo(AlarmModel a) {
    final idx = _alarms.indexOf(a);
    setState(() { _alarms.remove(a); });
    HapticFeedback.mediumImpact();
    _deactivateNow(a);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Alarm "${a.label}" cancelled'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Theme.of(context).colorScheme.primary,
          onPressed: () {
            _reactivateNow(a);
            setState(() {
              if (idx >= 0 && idx <= _alarms.length) {
                _alarms.insert(idx, a);
              } else {
                _alarms.add(a);
              }
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    ).closed.then((reason) {
      if (reason != SnackBarClosedReason.action) {
        _doCancel(a);
      }
    });
  }

  Future<void> _doCancel(AlarmModel a) async {
    if (a.androidAlarmId != null) {
      await AlarmService().cancelAlarm(a.androidAlarmId!);
    }
    await WidgetProvider.refresh();
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
          const Text('Alarms',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              )),
          const Spacer(),
          if (_alarms.isNotEmpty)
            Text('${_alarms.length} active',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _load,
            child: const Icon(Icons.refresh,
                color: AppColors.textSecondary, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    if (_alarms.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.alarm_off, size: 40, color: AppColors.textSecondary),
            SizedBox(height: 14),
            Text('No alarms set',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            SizedBox(height: 6),
            Text('"set an alarm for 7am"',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _alarms.length,
      itemBuilder: (ctx, i) => _alarmCard(_alarms[i]),
    );
  }

  Widget _alarmCard(AlarmModel a) {
    final next = _nextFire(a);
    final accent = Theme.of(context).colorScheme.primary;
    return Dismissible(
      key: Key('alarm_${a.id ?? a.androidAlarmId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.alarm.withValues(alpha: 0.15),
        child: const Icon(Icons.close, color: AppColors.alarm, size: 18),
      ),
      onDismissed: (_) => _cancelWithUndo(a),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 5, 14, 5),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(left: BorderSide(color: AppColors.alarm, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(DateHelper.formatTime(a.alarmTime),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        color: AppColors.surfaceHigh,
                        child: Text(_recurrenceLabel(a.recurrence),
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 9)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('Rings ${_whenLabel(next)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: accent, fontSize: 11)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _cancelWithUndo(a),
              icon: const Icon(Icons.close,
                  color: AppColors.textSecondary, size: 18),
              tooltip: 'Cancel alarm',
            ),
          ],
        ),
      ),
    );
  }
}
