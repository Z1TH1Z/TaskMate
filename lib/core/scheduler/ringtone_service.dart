import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lets the user choose the alarm sound. The actual picking is done by the
/// native system ringtone picker (see MainActivity.kt) which returns a
/// content:// URI the OS can read — the only reliable way to feed a custom
/// sound to a notification channel on modern Android.
///
/// Android locks a notification channel's sound at creation time, so we can't
/// mutate `taskmate_alarms` in place. Instead each pick bumps a version counter
/// and the alarm fires on a fresh `taskmate_alarms_v{n}` channel built with the
/// chosen sound. The previous channel is deleted so Settings doesn't accumulate
/// stale "Alarms" entries.
class RingtoneService {
  static const _channel = MethodChannel('taskmate/ringtone');

  static const keyUri = 'alarm_sound_uri';
  static const keyTitle = 'alarm_sound_title';
  static const keyVersion = 'alarm_channel_version';

  static const baseChannelId = 'taskmate_alarms';

  /// The notification channel id the next alarm should fire on, given the
  /// currently selected sound. Defaults to the base channel (system alarm
  /// sound) when the user hasn't picked anything.
  static String channelIdFor(SharedPreferences prefs) {
    final uri = prefs.getString(keyUri);
    if (uri == null || uri.isEmpty) return baseChannelId;
    final version = prefs.getInt(keyVersion) ?? 0;
    return '${baseChannelId}_v$version';
  }

  /// Current selection's display title, or null for the default alarm sound.
  Future<String?> currentTitle() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(keyUri);
    if (uri == null || uri.isEmpty) return null;
    return prefs.getString(keyTitle);
  }

  /// Opens the system ringtone picker. Returns the new title on success, or
  /// null if the user cancelled (selection unchanged).
  Future<String?> pickRingtone() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(keyUri);

    final result = await _channel.invokeMethod<dynamic>(
      'pickRingtone',
      {'currentUri': current},
    );
    if (result == null) return null; // cancelled

    final map = Map<String, dynamic>.from(result as Map);
    final uri = map['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    final title = (map['title'] as String?) ?? 'Custom sound';

    await _applySelection(prefs, uri, title);
    return title;
  }

  /// Reset to the default system alarm sound.
  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await _deleteCurrentVersionedChannel(prefs);
    await prefs.remove(keyUri);
    await prefs.remove(keyTitle);
  }

  Future<void> _applySelection(
      SharedPreferences prefs, String uri, String title) async {
    // Remove the previously created versioned channel before bumping.
    await _deleteCurrentVersionedChannel(prefs);

    final version = (prefs.getInt(keyVersion) ?? 0) + 1;
    await prefs.setInt(keyVersion, version);
    await prefs.setString(keyUri, uri);
    await prefs.setString(keyTitle, title);

    // Pre-create the new channel so the sound is locked in immediately and a
    // test/play works before the next alarm fires.
    await _createAlarmChannel('${baseChannelId}_v$version', uri);
  }

  Future<void> _deleteCurrentVersionedChannel(SharedPreferences prefs) async {
    final uri = prefs.getString(keyUri);
    if (uri == null || uri.isEmpty) return;
    final version = prefs.getInt(keyVersion) ?? 0;
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.deleteNotificationChannel('${baseChannelId}_v$version');
  }

  static Future<void> _createAlarmChannel(String id, String? soundUri) async {
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(AndroidNotificationChannel(
      id,
      'Alarms',
      description: 'Ringing alarms',
      importance: Importance.max,
      playSound: true,
      sound: (soundUri != null && soundUri.isNotEmpty)
          ? UriAndroidNotificationSound(soundUri)
          : null,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
  }

  /// Fire the alarm sound right now so the user can preview their choice.
  Future<void> playPreview() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final fln = FlutterLocalNotificationsPlugin();
    await fln.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    final channelId = channelIdFor(prefs);
    final soundUri = prefs.getString(keyUri);
    await _createAlarmChannel(channelId, soundUri);
    await fln.show(
      999001,
      'Alarm sound preview',
      prefs.getString(keyTitle) ?? 'Default alarm sound',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Alarms',
          channelDescription: 'Ringing alarms',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          playSound: true,
          sound: (soundUri != null && soundUri.isNotEmpty)
              ? UriAndroidNotificationSound(soundUri)
              : null,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
          vibrationPattern:
              Int64List.fromList(<int>[0, 600, 300, 600]),
          autoCancel: true,
          timeoutAfter: 8000,
        ),
      ),
    );
  }
}
