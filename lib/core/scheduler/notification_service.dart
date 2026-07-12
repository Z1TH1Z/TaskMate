import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'alarm_service.dart' show reminderActionCallback;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _fln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: reminderActionCallback,
      onDidReceiveBackgroundNotificationResponse: reminderActionCallback,
    );

    const channel = AndroidNotificationChannel(
      'reminders',
      'Reminders',
      description: 'Task reminders and recurring notifications',
      importance: Importance.high,
    );
    await _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Channel ID must match what alarmCallback uses ('taskmate_alarms').
    const alarmChannel = AndroidNotificationChannel(
      'taskmate_alarms',
      'Alarms',
      description: 'One-time and recurring alarms',
      importance: Importance.max,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    await _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(alarmChannel);
  }

  Future<void> showSimple({
    required int id,
    required String title,
    required String body,
  }) async {
    await _fln.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  Future<void> cancel(int id) async {
    await _fln.cancel(id);
  }
}
