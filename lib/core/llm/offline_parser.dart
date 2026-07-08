/// A tiny, dependency-free rule-based parser used ONLY as a fallback when the
/// Groq API is unreachable or rate-limited. It recognises a handful of common,
/// high-confidence phrasings and emits the SAME raw-intent maps that
/// [GroqService.parseMessage] returns, so the output flows through the existing
/// [IntentParser] and [IntentRouter] unchanged.
///
/// Design rule: precision over recall. If a message isn't confidently
/// understood, return an empty list so the caller can show the normal
/// "couldn't reach the AI" message instead of guessing wrong.
class OfflineParser {
  /// Returns raw intent maps, or an empty list if nothing matched confidently.
  static List<Map<String, dynamic>> parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return [];
    final msg = text.toLowerCase();

    // Order matters: more specific / higher-intent patterns first.
    final reminder = _reminder(text, msg);
    if (reminder != null) return [reminder];

    final alarm = _alarm(text, msg);
    if (alarm != null) return [alarm];

    final list = _listAdd(text, msg);
    if (list != null) return [list];

    final complete = _complete(text, msg);
    if (complete != null) return [complete];

    final query = _query(msg);
    if (query != null) return [query];

    final todo = _todo(text, msg);
    if (todo != null) return [todo];

    return [];
  }

  // ---- individual matchers ----

  static Map<String, dynamic>? _reminder(String text, String msg) {
    // "remind me to <task> at/by/in <time>" (the "to" is optional).
    final m = RegExp(r'remind me (?:to |that |about )?(.+)', caseSensitive: false)
        .firstMatch(text);
    if (m == null) return null;

    var rest = m.group(1)!.trim();
    final when = _extractWhen(rest.toLowerCase());

    // Strip the time phrase off the tail of the task text if we found one.
    String title = rest;
    if (when != null && when.matchStart >= 0) {
      title = rest.substring(0, when.matchStart).trim();
    }
    title = _tidyTitle(title);
    if (title.isEmpty) title = rest;

    final dt = when?.dateTime ?? _defaultReminderTime();
    return {
      'type': 'reminder',
      'title': title,
      'remind_at': _fmtDateTime(dt),
      'notes': null,
    };
  }

  static Map<String, dynamic>? _alarm(String text, String msg) {
    // "set an alarm at 7", "alarm for 6:30 am", "wake me up at 5am".
    if (!RegExp(r'\balarm\b|\bwake me\b', caseSensitive: false).hasMatch(msg)) {
      return null;
    }
    final when = _extractWhen(msg);
    if (when == null || when.timeOfDayOnly == null) return null; // need a clock time

    final recurrence = RegExp(r'\bevery day\b|\bdaily\b').hasMatch(msg)
        ? 'daily'
        : (RegExp(r'weekday|mon(?:day)?\s*(?:to|-|through)\s*fri').hasMatch(msg)
            ? 'weekdays'
            : 'none');

    return {
      'type': 'alarm',
      'times': [when.timeOfDayOnly!],
      'label': 'Alarm',
      'recurrence': recurrence,
    };
  }

  static Map<String, dynamic>? _listAdd(String text, String msg) {
    // "add <items> to my <list> list" / "add <items> to <list>".
    final m = RegExp(r'add (.+?) to (?:my |the )?(.+)', caseSensitive: false)
        .firstMatch(text);
    if (m == null) return null;

    final itemsRaw = m.group(1)!.trim();
    var listName = m.group(2)!.trim();
    listName = listName.replaceAll(RegExp(r'\s+list$', caseSensitive: false), '').trim();
    if (listName.isEmpty) return null;

    final category = _categoryFor(listName.toLowerCase());
    // Prefer the canonical category name as the list name (matches the online
    // behaviour that steers items into Movies/Shows/Books rather than ad-hoc).
    final canonical = _canonicalListName(category, listName);

    final items = itemsRaw
        .split(RegExp(r'\s*,\s*|\s+and\s+', caseSensitive: false))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => {'title': s, 'notes': null})
        .toList();
    if (items.isEmpty) return null;

    return {
      'type': 'list',
      'action': 'add',
      'list_name': canonical,
      'category': category,
      'items': items,
    };
  }

  static Map<String, dynamic>? _complete(String text, String msg) {
    // Cancel / clear / mark done.
    if (RegExp(r'\b(cancel|clear|reset)\s+(everything|all|it all)\b').hasMatch(msg)) {
      return {'type': 'complete', 'search_term': '*', 'scope': 'all'};
    }
    if (RegExp(r'\b(cancel|clear)\s+all\s+alarms?\b').hasMatch(msg)) {
      return {'type': 'complete', 'search_term': '*', 'scope': 'alarms'};
    }
    final m = RegExp(
            r'\b(?:cancel|delete|remove|done with|finished|complete)\s+(?:the |my )?(.+)',
            caseSensitive: false)
        .firstMatch(text);
    if (m != null) {
      final term = _tidyTitle(m.group(1)!.trim());
      if (term.isNotEmpty && term.length <= 60) {
        return {'type': 'complete', 'search_term': term, 'scope': 'all'};
      }
    }
    return null;
  }

  static Map<String, dynamic>? _query(String msg) {
    final asksToShow = RegExp(
            r"what('?s| is| do i have)|show|list|do i have|whats?\b",
            caseSensitive: false)
        .hasMatch(msg);
    if (!asksToShow && !RegExp(r'\btoday\b|\bdue\b').hasMatch(msg)) return null;

    if (RegExp(r'\balarms?\b').hasMatch(msg)) return {'type': 'query', 'filter': 'alarms'};
    if (RegExp(r'\breminders?\b').hasMatch(msg)) return {'type': 'query', 'filter': 'reminders'};
    if (RegExp(r'\btodos?\b').hasMatch(msg)) return {'type': 'query', 'filter': 'todos'};
    if (RegExp(r'\blists?\b').hasMatch(msg)) return {'type': 'query', 'filter': 'list'};
    if (RegExp(r'\boverdue\b').hasMatch(msg)) return {'type': 'query', 'filter': 'overdue'};
    if (RegExp(r'\bweek\b').hasMatch(msg)) return {'type': 'query', 'filter': 'week'};
    if (RegExp(r'\btoday\b|\bdue\b').hasMatch(msg)) return {'type': 'query', 'filter': 'today'};
    if (asksToShow && RegExp(r'\btasks?\b').hasMatch(msg)) {
      return {'type': 'query', 'filter': 'all'};
    }
    return null;
  }

  static Map<String, dynamic>? _todo(String text, String msg) {
    final m = RegExp(r'\b(?:todo|add task|new task)\s*:?\s*(.+)', caseSensitive: false)
        .firstMatch(text);
    if (m == null) return null;
    final title = _tidyTitle(m.group(1)!.trim());
    if (title.isEmpty) return null;
    return {'type': 'todo', 'title': title, 'due_date': null, 'priority': 'medium'};
  }

  // ---- time extraction ----

  /// A parsed time reference within a message.
  static _When? _extractWhen(String msg) {
    final now = DateTime.now();

    // Relative: "in 30 minutes", "in 2 hours", "in 1 hr".
    final rel = RegExp(r'\bin\s+(\d{1,3})\s*(min(?:ute)?s?|h(?:ou)?rs?)\b',
            caseSensitive: false)
        .firstMatch(msg);
    if (rel != null) {
      final n = int.parse(rel.group(1)!);
      final unit = rel.group(2)!.toLowerCase();
      final dt = unit.startsWith('h')
          ? now.add(Duration(hours: n))
          : now.add(Duration(minutes: n));
      return _When(dateTime: dt, matchStart: rel.start, timeOfDayOnly: _hhmm(dt));
    }

    // Named times.
    const named = {
      'midnight': 0,
      'noon': 12,
      'morning': 8,
      'afternoon': 13,
      'evening': 18,
      'night': 21,
    };
    for (final e in named.entries) {
      final idx = msg.indexOf(e.key);
      if (idx >= 0) {
        final dt = _todayAt(now, e.value, 0);
        return _When(dateTime: dt, matchStart: idx, timeOfDayOnly: _hhmm(dt));
      }
    }

    // Absolute clock: "at 7", "at 7:30", "7 pm", "6:15am". Require an "at"/"by"
    // anchor OR an am/pm suffix so bare numbers in task text aren't misread.
    // The anchor is captured as group 1 — it's part of the match, so checking
    // the text *before* the match would never find it.
    final clock = RegExp(
            r'\b(at|by)?\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?',
            caseSensitive: false)
        .allMatches(msg);
    for (final c in clock) {
      final hasAnchor = c.group(1) != null;
      final period = c.group(4);
      if (period == null && !hasAnchor) continue; // too ambiguous
      var hour = int.parse(c.group(2)!);
      final minute = int.tryParse(c.group(3) ?? '') ?? 0;
      if (hour > 23 || minute > 59) continue;
      if (period != null) {
        final pm = period.toLowerCase().startsWith('p');
        if (pm && hour < 12) hour += 12;
        if (!pm && hour == 12) hour = 0;
      }
      var dt = _todayAt(now, hour, minute);
      if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
      return _When(dateTime: dt, matchStart: c.start, timeOfDayOnly: _hhmm(dt));
    }

    return null;
  }

  // ---- helpers ----

  static DateTime _defaultReminderTime() {
    final now = DateTime.now();
    var dt = _todayAt(now, 9, 0);
    if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));
    return dt;
  }

  static DateTime _todayAt(DateTime now, int h, int m) =>
      DateTime(now.year, now.month, now.day, h, m);

  static String _hhmm(DateTime dt) =>
      '${_two(dt.hour)}:${_two(dt.minute)}';

  static String _fmtDateTime(DateTime dt) =>
      '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _tidyTitle(String s) {
    var out = s.trim();
    // Drop trailing connective words left over after removing a time phrase.
    out = out.replaceAll(
        RegExp(r'[\s,]*\b(at|by|in|on|the|to|please)\b[\s,]*$',
            caseSensitive: false),
        '');
    return out.trim();
  }

  static String _categoryFor(String listName) {
    if (RegExp(r'movie|film').hasMatch(listName)) return 'movies';
    if (RegExp(r'anime').hasMatch(listName)) return 'anime';
    if (RegExp(r'show|series|web series|tv').hasMatch(listName)) return 'shows';
    if (RegExp(r'book|read').hasMatch(listName)) return 'books';
    return 'general';
  }

  static String _canonicalListName(String category, String fallback) {
    switch (category) {
      case 'movies':
        return 'Movies';
      case 'anime':
        return 'Anime';
      case 'shows':
        return 'Shows';
      case 'books':
        return 'Books';
      default:
        // Title-case the user's own name.
        return fallback
            .split(RegExp(r'\s+'))
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }
}

class _When {
  final DateTime dateTime;
  final int matchStart;
  /// 'HH:MM' when the reference is a clock time (used by alarms); null for
  /// relative-only offsets that still yield a concrete [dateTime].
  final String? timeOfDayOnly;
  _When({required this.dateTime, required this.matchStart, this.timeOfDayOnly});
}
