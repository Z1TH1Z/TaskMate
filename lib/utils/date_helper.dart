import 'package:intl/intl.dart';

class DateHelper {
  static String formatDisplay(String? dateStr) {
    if (dateStr == null) return '';
    try {
      if (dateStr.length == 10) {
        final dt = DateTime.parse(dateStr);
        return DateFormat('d MMM yyyy').format(dt);
      }
      final dt = DateTime.parse(dateStr.replaceFirst(' ', 'T'));
      return DateFormat('d MMM yyyy, h:mm a').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  static String formatTime(String? timeStr) {
    if (timeStr == null) return '';
    try {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final dt = DateTime(2000, 1, 1, hour, minute);
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return timeStr;
    }
  }

  static String nowIso() => DateTime.now().toIso8601String();
}
