import 'package:flutter_test/flutter_test.dart';
import 'package:taskmate/core/llm/intent_parser.dart';
import 'package:taskmate/models/intents/alarm_intent.dart';

void main() {
  group('AM/PM time correction', () {
    test('8 AM stays as 08:00', () {
      final result = IntentParser.correctTimeForTest('08:00', 'set alarm at 8 am');
      expect(result, '08:00');
    });

    test('8 PM corrects 08:00 to 20:00', () {
      final result = IntentParser.correctTimeForTest('08:00', 'set alarm at 8 pm');
      expect(result, '20:00');
    });

    test('8:30 AM stays as 08:30', () {
      final result = IntentParser.correctTimeForTest('08:30', 'set alarm at 8:30 AM');
      expect(result, '08:30');
    });

    test('8:30 PM corrects 08:30 to 20:30', () {
      final result = IntentParser.correctTimeForTest('08:30', 'set alarm at 8:30 PM');
      expect(result, '20:30');
    });

    test('12 AM corrects 12:00 to 00:00', () {
      final result = IntentParser.correctTimeForTest('12:00', 'alarm at 12 am');
      expect(result, '00:00');
    });

    test('12 PM stays as 12:00', () {
      final result = IntentParser.correctTimeForTest('12:00', 'alarm at 12 pm');
      expect(result, '12:00');
    });

    test('12:30 AM corrects 12:30 to 00:30', () {
      final result = IntentParser.correctTimeForTest('12:30', 'alarm at 12:30 am');
      expect(result, '00:30');
    });

    test('12:30 PM stays as 12:30', () {
      final result = IntentParser.correctTimeForTest('12:30', 'alarm at 12:30 pm');
      expect(result, '12:30');
    });

    test('already correct 20:00 for 8 PM is unchanged', () {
      final result = IntentParser.correctTimeForTest('20:00', 'alarm at 8 pm');
      expect(result, '20:00');
    });

    test('no AM/PM in message leaves time unchanged', () {
      final result = IntentParser.correctTimeForTest('15:00', 'alarm at 3');
      expect(result, '15:00');
    });
  });

  group('Multi-alarm spacing', () {
    test('3 alarms before 8 AM (480 min) clusters near target', () {
      final times = IntentParser.computeAlarmTimesForTest(480, 3);
      expect(times.length, 3);
      // All alarms should be before target
      for (final t in times) {
        expect(t, lessThan(480));
      }
      // Last alarm should be close to target (within 20 min)
      expect(times.last, greaterThanOrEqualTo(460));
      // First alarm shouldn't be more than 60 min before target
      expect(times.first, greaterThanOrEqualTo(420));
    });

    test('2 alarms before 8 AM', () {
      final times = IntentParser.computeAlarmTimesForTest(480, 2);
      expect(times.length, 2);
      expect(times[0], 450); // 7:30
      expect(times[1], 470); // 7:50
    });

    test('5 alarms before 8 AM', () {
      final times = IntentParser.computeAlarmTimesForTest(480, 5);
      expect(times.length, 5);
      for (final t in times) {
        expect(t, lessThan(480));
      }
      // Last alarm within 5 min of target
      expect(times.last, greaterThanOrEqualTo(475));
    });

    test('1 alarm before target', () {
      final times = IntentParser.computeAlarmTimesForTest(480, 1);
      expect(times.length, 1);
      expect(times[0], 475); // 5 min before
    });

    test('all times are sorted ascending', () {
      final times = IntentParser.computeAlarmTimesForTest(480, 4);
      for (int i = 1; i < times.length; i++) {
        expect(times[i], greaterThan(times[i - 1]));
      }
    });
  });

  group('IntentParser.parse with AM/PM correction', () {
    test('alarm intent times are corrected', () {
      final parser = IntentParser();
      final intents = parser.parse([
        {'type': 'alarm', 'times': ['08:30'], 'label': 'Wake up', 'recurrence': 'none'}
      ], 'set alarm at 8:30 PM');

      expect(intents.length, 1);
      final alarm = intents[0] as AlarmIntent;
      expect(alarm.times[0], '20:30');
    });

    test('multi-alarm expansion via target_time and count', () {
      final parser = IntentParser();
      final intents = parser.parse([
        {'type': 'alarm', 'times': [], 'label': 'Wake up', 'recurrence': 'none',
         'target_time': '08:00', 'count': 3}
      ], 'set 3 alarms before 8 AM');

      expect(intents.length, 3);
      for (final intent in intents) {
        final alarm = intent as AlarmIntent;
        expect(alarm.times.length, 1);
        // All times should be before 08:00
        final parts = alarm.times[0].split(':');
        final totalMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        expect(totalMin, lessThan(480));
      }
    });
  });
}
