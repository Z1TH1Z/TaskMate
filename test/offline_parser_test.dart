import 'package:flutter_test/flutter_test.dart';
import 'package:taskmate/core/llm/offline_parser.dart';

void main() {
  group('OfflineParser', () {
    test('parses a reminder with an absolute time', () {
      final out = OfflineParser.parse('remind me to call mom at 6pm');
      expect(out.length, 1);
      expect(out.first['type'], 'reminder');
      expect(out.first['title'], 'call mom');
      expect((out.first['remind_at'] as String).endsWith('18:00'), isTrue);
    });

    test('parses a relative reminder and strips the time phrase', () {
      final out = OfflineParser.parse('remind me to drink water in 5 minutes');
      expect(out.length, 1);
      expect(out.first['type'], 'reminder');
      expect(out.first['title'], 'drink water');
    });

    test('recognises an "at" time with no am/pm and strips it from the title', () {
      final out = OfflineParser.parse('remind me to sleep at 10');
      expect(out.length, 1);
      expect(out.first['type'], 'reminder');
      expect(out.first['title'], 'sleep');
      expect((out.first['remind_at'] as String).endsWith('10:00'), isTrue);
    });

    test('parses an alarm', () {
      final out = OfflineParser.parse('set an alarm at 7am');
      expect(out.length, 1);
      expect(out.first['type'], 'alarm');
      expect((out.first['times'] as List).first, '07:00');
      expect(out.first['recurrence'], 'none');
    });

    test('parses a daily alarm', () {
      final out = OfflineParser.parse('set an alarm at 7am every day');
      expect(out.first['recurrence'], 'daily');
    });

    test('parses a list add and canonicalises the category', () {
      final out = OfflineParser.parse('add Inception to my movies list');
      expect(out.length, 1);
      expect(out.first['type'], 'list');
      expect(out.first['action'], 'add');
      expect(out.first['category'], 'movies');
      expect(out.first['list_name'], 'Movies');
      expect((out.first['items'] as List).length, 1);
      expect((out.first['items'] as List).first['title'], 'Inception');
    });

    test('splits multiple list items', () {
      final out = OfflineParser.parse('add eggs, milk and bread to groceries');
      final items = out.first['items'] as List;
      expect(items.length, 3);
    });

    test('parses a today query', () {
      final out = OfflineParser.parse("what's due today");
      expect(out.first['type'], 'query');
      expect(out.first['filter'], 'today');
    });

    test('parses a cancel/complete', () {
      final out = OfflineParser.parse('cancel gym');
      expect(out.first['type'], 'complete');
      expect(out.first['search_term'], 'gym');
      expect(out.first['scope'], 'all');
    });

    test('cancel everything is a wildcard', () {
      final out = OfflineParser.parse('cancel everything');
      expect(out.first['search_term'], '*');
      expect(out.first['scope'], 'all');
    });

    test('returns empty for unrecognised input', () {
      expect(OfflineParser.parse('asldkfj qwerty zzz'), isEmpty);
      expect(OfflineParser.parse(''), isEmpty);
    });
  });
}
