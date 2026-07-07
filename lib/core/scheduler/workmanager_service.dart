import 'package:workmanager/workmanager.dart';

class WorkmanagerService {
  static final WorkmanagerService _instance = WorkmanagerService._();
  factory WorkmanagerService() => _instance;
  WorkmanagerService._();

  // Recurring reminders are scheduled via AlarmService.scheduleRecurringReminder
  // (android_alarm_manager_plus), not WorkManager — its zonedSchedule-based
  // notifications never displayed on-device. WorkManager is kept only for the
  // daily morning briefing below.

  Future<void> registerMorningBriefing() async {
    await Workmanager().registerPeriodicTask(
      'morning_briefing',
      'morningBriefing',
      frequency: const Duration(hours: 24),
      initialDelay: _delayUntil8AM(),
      constraints: Constraints(networkType: NetworkType.notRequired),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  Duration _delayUntil8AM() {
    final now = DateTime.now();
    var next8am = DateTime(now.year, now.month, now.day, 8, 0);
    if (now.isAfter(next8am)) next8am = next8am.add(const Duration(days: 1));
    return next8am.difference(now);
  }
}
