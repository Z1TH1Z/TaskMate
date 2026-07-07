# TaskMate — Personal LLM Task Manager
## Final Build Blueprint v2

---

## 1. Stack

| Layer | Tool | Note |
|---|---|---|
| Framework | Flutter (Android only) | You know it |
| LLM | Groq `llama-3.1-8b-instant` | JSON mode, ~1.1s response |
| Local DB | `sqflite` | All data stays on device |
| Alarms | `android_alarm_manager_plus` | Pierces DND, shows in system clock |
| Notifications | `flutter_local_notifications` | One-time + persistent |
| Background jobs | `workmanager` | Recurring reminders, survives app kill + reboot |
| Widget | `home_widget` | Home screen widget |
| Voice input | `speech_to_text` | Free Android STT |
| Permissions | `permission_handler` | Runtime permission handling |
| Prefs | `shared_preferences` | Store API key locally |
| Date formatting | `intl` | Date/time helpers |

---

## 2. pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  sqflite: ^2.3.3
  path: ^1.9.0
  android_alarm_manager_plus: ^3.0.4
  flutter_local_notifications: ^17.2.3
  workmanager: ^0.5.2
  home_widget: ^0.4.1
  http: ^1.2.2
  speech_to_text: ^6.6.2
  permission_handler: ^11.3.1
  shared_preferences: ^2.3.2
  intl: ^0.19.0
```

---

## 3. AndroidManifest.xml

Add inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

Add inside `<application>`:

```xml
<!-- AlarmManager -->
<receiver
    android:name="dev.fluttercommunity.plus.androidalarmmanager.AlarmBroadcastReceiver"
    android:exported="true"/>
<service
    android:name="dev.fluttercommunity.plus.androidalarmmanager.AlarmService"
    android:exported="false"
    android:permission="android.permission.BIND_JOB_SERVICE"/>

<!-- Reboot receiver — reschedules alarms after phone restarts -->
<receiver
    android:name=".BootReceiver"
    android:exported="true">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED"/>
  </intent-filter>
</receiver>

<!-- WorkManager -->
<provider
    android:name="androidx.startup.InitializationProvider"
    android:authorities="${applicationId}.androidx-startup"
    android:exported="false"
    tools:node="merge">
  <meta-data
      android:name="androidx.work.WorkManagerInitializer"
      android:value="androidx.startup"/>
</provider>
```

---

## 4. Project Structure

```
lib/
├── main.dart                          # app init, WorkManager callback registration
├── app.dart                           # MaterialApp, routes
│
├── core/
│   ├── db/
│   │   ├── database.dart              # init, create tables, migrations
│   │   └── repositories/
│   │       ├── task_repository.dart   # CRUD for tasks + notification_ids
│   │       ├── list_repository.dart   # CRUD for lists + items
│   │       └── chat_repository.dart   # store/fetch last N messages
│   │
│   ├── llm/
│   │   ├── groq_service.dart          # HTTP call, injects datetime, sends history
│   │   ├── intent_parser.dart         # raw JSON string → List<Intent>
│   │   └── system_prompt.dart         # THE prompt — most critical file
│   │
│   ├── scheduler/
│   │   ├── alarm_service.dart         # AlarmManager: set, cancel, reschedule
│   │   ├── notification_service.dart  # schedule, cancel, persistent flags
│   │   └── workmanager_service.dart   # register/cancel recurring jobs
│   │
│   └── router/
│       └── intent_router.dart         # loops through intents[], routes each one
│
├── models/
│   ├── intents/
│   │   ├── base_intent.dart
│   │   ├── alarm_intent.dart
│   │   ├── reminder_intent.dart
│   │   ├── recurring_intent.dart
│   │   ├── list_intent.dart
│   │   ├── todo_intent.dart
│   │   ├── complete_intent.dart
│   │   ├── query_intent.dart
│   │   └── clarify_intent.dart
│   ├── task.dart
│   ├── task_list.dart
│   ├── list_item.dart
│   └── chat_message.dart
│
├── screens/
│   ├── setup/
│   │   └── api_key_screen.dart        # first-launch, store Groq key
│   ├── chat/
│   │   ├── chat_screen.dart           # main screen
│   │   └── chat_bubble.dart
│   ├── tasks/
│   │   ├── tasks_screen.dart
│   │   └── task_card.dart
│   └── lists/
│       ├── lists_screen.dart
│       └── list_detail_screen.dart
│
├── widget/
│   └── widget_provider.dart           # pushes data to home widget
│
└── utils/
    ├── date_helper.dart               # parse messy dates, format display
    └── id_generator.dart              # unique notification IDs
```

---

## 5. SQLite Schema

```sql
-- Tasks: reminders, recurring, todos
CREATE TABLE tasks (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  title             TEXT    NOT NULL,
  type              TEXT    NOT NULL,    -- 'reminder' | 'recurring' | 'todo'
  due_date          TEXT,               -- 'YYYY-MM-DD HH:MM'
  recurrence        TEXT,               -- 'daily' | 'weekdays' | 'weekly' | null
  recurrence_end    TEXT,               -- 'YYYY-MM-DD' | null
  skip_weekends     INTEGER DEFAULT 0,
  is_completed      INTEGER DEFAULT 0,
  notification_ids  TEXT    DEFAULT '[]', -- JSON int array e.g. [101,102,103]
  created_at        TEXT    NOT NULL
);

-- Alarms: appear in Android system clock
CREATE TABLE alarms (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  label            TEXT    NOT NULL,
  alarm_time       TEXT    NOT NULL,    -- 'HH:MM' 24hr
  recurrence       TEXT    DEFAULT 'none', -- 'none' | 'daily' | 'weekdays'
  is_active        INTEGER DEFAULT 1,
  android_alarm_id INTEGER,
  created_at       TEXT    NOT NULL
);

-- Lists: movies, anime, books, general
CREATE TABLE lists (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT NOT NULL,
  category   TEXT DEFAULT 'general',   -- 'movies' | 'anime' | 'books' | 'general'
  created_at TEXT NOT NULL
);

-- Items inside lists
CREATE TABLE list_items (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  list_id INTEGER NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
  title   TEXT    NOT NULL,
  notes   TEXT,                        -- release date, extra info
  is_done INTEGER DEFAULT 0,
  extra   TEXT    DEFAULT '{}'         -- JSON blob for future use
);

-- Chat history: last N messages sent to Groq for context
CREATE TABLE chat_history (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  role       TEXT NOT NULL,            -- 'user' | 'assistant'
  content    TEXT NOT NULL,
  created_at TEXT NOT NULL
);
```

---

## 6. The Groq System Prompt

**Tune this in Python until all test cases pass. Do not move to Flutter before this is solid.**

```
You are a personal task assistant embedded in an Android app.

Parse the user's message — which may be informal, abbreviated, contain typos,
or mix multiple requests — and return ONLY a valid JSON object.
No explanation. No markdown. No extra text. Just the JSON.

ALWAYS return this wrapper, even for a single intent:
{"intents": [ ... ]}

Current datetime: {INJECT_DATETIME}
Timezone: Asia/Kolkata

---

INTENT TYPES — each item in the intents array is one of:

### ALARM
Rings like a real alarm clock. Use when user wants to wake up or be alerted at a time.
{
  "type": "alarm",
  "times": ["07:30", "07:45", "08:00", "08:15", "08:30", "08:45", "09:00"],
  "label": "Wake up - class at 9",
  "recurrence": "none"
}
- recurrence: "none" | "daily" | "weekdays"
- For "from X to Y" → generate every 15 min from X to Y inclusive
- For "at X" → single time in array

### REMINDER
One-time notification at a specific date and time.
{
  "type": "reminder",
  "title": "Book bus to Chennai",
  "remind_at": "2026-06-15 20:00",
  "notes": "Travel on 16th"
}
- remind_at: "YYYY-MM-DD HH:MM"
- If no time given, default to 09:00
- If no year given, assume current year

### RECURRING
Repeating notification (not alarm). Fires on a schedule until end_date.
{
  "type": "recurring",
  "title": "VIT CDC Assessment",
  "notify_times": ["10:00", "15:00", "20:00"],
  "recurrence": "weekdays",
  "end_date": "2026-07-20"
}
- recurrence: "daily" | "weekdays" | "weekly"
- "every day except weekends" / "every weekday" / "Mon-Fri" → "weekdays"
- If no end_date given, set null (runs indefinitely until user says done)
- If user says "X times a day" with no specific times, spread evenly across waking hours

### LIST
Add items to a watchlist / reading list / general list.
{
  "type": "list",
  "action": "create",
  "list_name": "Movies",
  "category": "movies",
  "items": [
    {"title": "Backrooms", "notes": null}
  ]
}
- action: "create" | "add"
- category: "movies" | "anime" | "books" | "general"
- If list already likely exists (movies list exists), use action: "add"
- notes: use for release dates or any extra info the user mentions

### TODO
Simple one-off task, no repeating notification.
{
  "type": "todo",
  "title": "Submit SIH project report",
  "due_date": "2026-06-20",
  "priority": "high"
}
- priority: "high" | "medium" | "low" — infer from urgency in message
- due_date: "YYYY-MM-DD" or null

### COMPLETE
User says they finished something or wants to stop reminders for something.
{
  "type": "complete",
  "search_term": "vit assessment",
  "scope": "today"
}
- search_term: key words to match against task titles in the DB
- scope: "today" (cancel today only) | "all" (cancel everything, mark done)
- "done for today" / "finished today" → scope: "today"
- "cancel all" / "I'm done with it" / "remove it" → scope: "all"

### QUERY
User is asking what tasks or reminders they have.
{
  "type": "query",
  "filter": "today"
}
- filter: "today" | "week" | "all" | "overdue"

### CLARIFY
You cannot create the intent without more information.
{
  "type": "clarify",
  "message": "When is He-Man releasing? I'll add it to your list once you tell me.",
  "missing_for": "He-Man release date"
}
- Use this when a critical piece of info is missing
- Be specific about what you need — don't ask vague questions

---

MULTI-INTENT RULES:
- One message can produce multiple intents — include ALL of them in the array
- Example: "set alarm 7:30 and add backrooms to watchlist" → [alarm intent, list intent]
- If SOME items in a request are clear and SOME need info:
  → include the clear intents AND a clarify intent for the unclear ones
  → Example: "add backrooms and he man (no release date)" →
    [list intent with backrooms] + [clarify intent asking for he man release date]
- Process what you can, clarify what you can't

PARSING RULES:
- Handle typos, abbreviations, informal language naturally
- "tmrw" = tomorrow, "abt" = about, "n" = and, "cus/cuz" = because
- Times: "7 30" / "7:30" / "730" / "half 8" → all valid, parse to "HH:MM"
- "ish" after a time → use that time exactly (can't guess)
- Dates without year → assume current year
- "every weekday" / "except weekends" / "Mon-Fri" → recurrence: "weekdays"
- "3 times a day" with no times → ["08:00", "13:00", "19:00"]
- "morning" → "08:00", "afternoon" → "13:00", "evening" → "18:00", "night" → "21:00"
- Always output times in 24hr "HH:MM" format
- Always output dates in "YYYY-MM-DD" format

OUTPUT: ONLY the JSON object {"intents": [...]}. Nothing else.
```

---

## 7. Core Service Code

### groq_service.dart
```dart
class GroqService {
  static const _model = 'llama-3.1-8b-instant';
  static const _url = 'https://api.groq.com/openai/v1/chat/completions';

  final String apiKey;
  GroqService(this.apiKey);

  Future<List<Map<String, dynamic>>> parseMessage(
    String userMessage,
    List<Map<String, String>> chatHistory, // last 6 messages
  ) async {
    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    final response = await http.post(
      Uri.parse(_url),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _model,
        'temperature': 0.1,
        'max_tokens': 500,
        'response_format': {'type': 'json_object'}, // NEVER remove this
        'messages': [
          {'role': 'system', 'content': buildPrompt(now)},
          ...chatHistory,                            // context for follow-ups
          {'role': 'user', 'content': userMessage},
        ],
      }),
    );

    final body = jsonDecode(response.body);
    final raw = body['choices'][0]['message']['content'] as String;

    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(parsed['intents']);
    } catch (_) {
      // Retry once with explicit nudge
      return await _retryWithStricterPrompt(userMessage, chatHistory, now);
    }
  }
}
```

### intent_router.dart
```dart
class IntentRouter {
  Future<List<String>> route(List<Map<String, dynamic>> intents) async {
    final responses = <String>[];

    for (final intent in intents) {
      final reply = await _handle(intent);
      if (reply != null) responses.add(reply);
    }

    return responses; // all confirmations shown in chat
  }

  Future<String?> _handle(Map<String, dynamic> intent) async {
    switch (intent['type']) {
      case 'alarm':     return await _handleAlarm(intent);
      case 'reminder':  return await _handleReminder(intent);
      case 'recurring': return await _handleRecurring(intent);
      case 'list':      return await _handleList(intent);
      case 'todo':      return await _handleTodo(intent);
      case 'complete':  return await _handleComplete(intent);
      case 'query':     return await _handleQuery(intent);
      case 'clarify':   return intent['message'] as String; // show in chat
      default:          return "Didn't understand that part.";
    }
  }
}
```

### notification_service.dart — Persistent Reminder
```dart
Future<int> showPersistentReminder({
  required int id,
  required String title,
  required String body,
}) async {
  await fln.show(
    id, title, body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders', 'Reminders',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,         // cannot be swiped away
        autoCancel: false,
        actions: [
          AndroidNotificationAction('done_today', 'Done Today'),
          AndroidNotificationAction('snooze_1h',  'Snooze 1 hr'),
          AndroidNotificationAction('done_all',   'Done Forever'),
        ],
      ),
    ),
  );
  return id;
}
```

### workmanager_service.dart — Recurring Jobs
```dart
// Register daily job for a recurring task
Future<void> registerRecurring({
  required int taskId,
  required String title,
  required List<String> times,   // ["10:00", "15:00", "20:00"]
  required bool skipWeekends,
  DateTime? endDate,
}) async {
  await Workmanager().registerPeriodicTask(
    'recurring_$taskId',
    'fireReminderNotifications',
    frequency: const Duration(hours: 24),
    inputData: {
      'taskId': taskId,
      'title': title,
      'times': jsonEncode(times),
      'skipWeekends': skipWeekends,
      'endDate': endDate?.toIso8601String(),
    },
    constraints: Constraints(networkType: NetworkType.not_required),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

// Cancel a recurring job (when user says "done")
Future<void> cancelRecurring(int taskId) async {
  await Workmanager().cancelByUniqueName('recurring_$taskId');
}
```

```dart
// In main.dart — top-level function, required by WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'fireReminderNotifications') {
      final today = DateTime.now().weekday;
      final skipWeekends = inputData!['skipWeekends'] as bool;

      // Skip if weekend and task is weekdays-only
      if (skipWeekends && (today == DateTime.saturday || today == DateTime.sunday)) {
        return true;
      }

      // Check if past end date
      final endDateStr = inputData['endDate'] as String?;
      if (endDateStr != null) {
        final endDate = DateTime.parse(endDateStr);
        if (DateTime.now().isAfter(endDate)) {
          await Workmanager().cancelByUniqueName(taskName);
          return true;
        }
      }

      // Schedule today's notifications at exact times
      final times = List<String>.from(jsonDecode(inputData['times']));
      final notifService = NotificationService();
      for (final time in times) {
        final parts = time.split(':');
        final scheduledTime = DateTime.now().copyWith(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
          second: 0,
        );
        if (scheduledTime.isAfter(DateTime.now())) {
          await notifService.scheduleExact(
            id: generateId(),
            title: inputData['title'],
            scheduledAt: scheduledTime,
          );
        }
      }
    }

    if (taskName == 'morningBriefing') {
      // Query DB for today's tasks and fire a summary notification
      final db = await DatabaseHelper.instance.database;
      final tasks = await TaskRepository(db).getTasksDueToday();
      if (tasks.isNotEmpty) {
        final summary = tasks.map((t) => t.title).join(', ');
        await NotificationService().showSimple(
          id: 9999,
          title: 'Today',
          body: summary,
        );
      }
    }

    return true;
  });
}
```

### alarm_service.dart — Reboot Handling
```dart
// Reschedule all active alarms after reboot
// Called from BootReceiver (Kotlin/Java side) via method channel
Future<void> rescheduleAllAfterReboot() async {
  final db = await DatabaseHelper.instance.database;
  final alarms = await AlarmRepository(db).getActiveAlarms();

  for (final alarm in alarms) {
    await scheduleAlarm(
      id: alarm.androidAlarmId,
      time: alarm.alarmTime,
      label: alarm.label,
      recurrence: alarm.recurrence,
    );
  }
}
```

---

## 8. complete Intent — Cancel Flow

This is the flow that stops persistent notifications:

```dart
Future<String> _handleComplete(Map<String, dynamic> intent) async {
  final searchTerm = intent['search_term'] as String;
  final scope = intent['scope'] as String; // 'today' | 'all'

  // Fuzzy match against task titles
  final tasks = await taskRepo.searchByTitle(searchTerm);

  if (tasks.isEmpty) return "Couldn't find a task matching '$searchTerm'.";

  for (final task in tasks) {
    final ids = List<int>.from(jsonDecode(task.notificationIds));

    if (scope == 'today') {
      // Cancel only today's pending notifications
      for (final id in ids) {
        await notificationService.cancel(id);
      }
      await taskRepo.clearTodayNotifications(task.id);
      return "Got it. No more reminders for ${task.title} today.";

    } else {
      // Cancel everything and mark done
      for (final id in ids) {
        await notificationService.cancel(id);
      }
      await workmanagerService.cancelRecurring(task.id);
      await taskRepo.markComplete(task.id);
      return "${task.title} marked as done. All reminders cancelled.";
    }
  }
  return "Done.";
}
```

```dart
// In task_repository.dart
Future<List<Task>> searchByTitle(String term) async {
  final db = await _db;
  return (await db.query(
    'tasks',
    where: 'title LIKE ? AND is_completed = 0',
    whereArgs: ['%$term%'],
  )).map(Task.fromMap).toList();
}
```

---

## 9. Widget

Data pushed after every intent is processed:

```dart
Future<void> refreshWidget() async {
  final db = await DatabaseHelper.instance.database;
  final todayTasks = await TaskRepository(db).getTasksDueToday();
  final nextAlarm = await AlarmRepository(db).getNextAlarm();

  await HomeWidget.saveWidgetData('tasks_today', todayTasks.length);
  await HomeWidget.saveWidgetData('next_alarm', nextAlarm?.alarmTime ?? '--:--');
  await HomeWidget.saveWidgetData(
    'task_preview',
    todayTasks.isEmpty ? 'Nothing due today' : todayTasks.first.title,
  );
  await HomeWidget.updateWidget(androidName: 'TaskMateWidgetProvider');
}
```

Widget layout lives in `android/app/src/main/res/layout/taskmate_widget.xml` — pure Android XML, no Flutter UI.

---

## 10. Morning Briefing Setup

Register once at app first launch. Fires 8:00 AM daily.

```dart
// Calculate delay until next 8am
Duration _delayUntil8AM() {
  final now = DateTime.now();
  var next8am = DateTime(now.year, now.month, now.day, 8, 0);
  if (now.isAfter(next8am)) next8am = next8am.add(const Duration(days: 1));
  return next8am.difference(now);
}

await Workmanager().registerPeriodicTask(
  'morning_briefing',
  'morningBriefing',
  frequency: const Duration(hours: 24),
  initialDelay: _delayUntil8AM(),
  constraints: Constraints(networkType: NetworkType.not_required),
  existingWorkPolicy: ExistingWorkPolicy.keep,
);
```

---

## 11. First Launch Checklist

Show these permission requests in sequence on first open:

```dart
Future<void> requestAllPermissions() async {
  // 1. Notification permission (Android 13+)
  await Permission.notification.request();

  // 2. Exact alarm permission — opens system settings on Android 12+
  if (!await Permission.scheduleExactAlarm.isGranted) {
    await Permission.scheduleExactAlarm.request();
  }

  // 3. Battery optimisation whitelist
  if (!await Permission.ignoreBatteryOptimizations.isGranted) {
    await Permission.ignoreBatteryOptimizations.request();
    // This is critical — without it WorkManager gets throttled
  }

  // 4. Microphone (for voice input)
  await Permission.microphone.request();
}
```

---

## 12. Build Order — Follow Exactly

### Phase 1 — Days 1-2: Prompt Validation (Python only)

Do not open Flutter. Run this until all test cases produce correct JSON.

```python
import groq, json
from datetime import datetime

client = groq.Groq(api_key="YOUR_KEY")

def parse(msg, history=[]):
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    r = client.chat.completions.create(
        model="llama-3.1-8b-instant",
        temperature=0.1,
        response_format={"type": "json_object"},
        messages=[
            {"role": "system", "content": PROMPT.replace("{INJECT_DATETIME}", now)},
            *history,
            {"role": "user", "content": msg}
        ]
    )
    return json.loads(r.choices[0].message.content)

# REQUIRED test cases — all must pass before Phase 2
cases = [
    "bro class at 9 tmrw set alarms",
    "ugh vit cdc thing remind me like 3 times a day except weekends",
    "add backrooms n he man to watchlist",              # 2 items, 1 needs clarify
    "set alarms 7 30 to 9 and also remind me abt assessment",  # 2 intents
    "bus to chennai 16th june remind me",
    "done with the assessment today finally",           # scope: today
    "cancel the vit reminders",                         # scope: all
    "what do i have tmrw",
    "anime list add aot and vinland saga",
    "alarm 6 30 daily",
    "remind me to drink water 3 times a day",
    "yo set an alarm for 7 ish",                        # ambiguous time
    "i have to submit project before june 20",
    "add he man to movies",                             # follow-up after clarify
]

for c in cases:
    result = parse(c)
    assert 'intents' in result, f"FAIL — no intents array: {c}"
    print(f"✓ {c}")
    print(json.dumps(result, indent=2))
    print()
```

### Phase 2 — Days 3-4: SQLite Layer

- `database.dart` — init, table creation
- All repositories — CRUD, searchByTitle, getTasksDueToday, getActiveAlarms
- Test with dummy data, no Flutter UI
- Verify the notification_ids cancel flow works on paper

### Phase 3 — Days 5-6: Alarm + Notification + WorkManager

- Set ONE alarm → confirm it shows in Android clock and rings
- Set ONE WorkManager job with 15min frequency → confirm it fires
- Show ONE persistent notification → confirm Done/Snooze actions work
- Handle boot receiver → restart phone, confirm alarm reappears
- Request battery optimisation whitelist → confirm WorkManager fires reliably

### Phase 4 — Days 7-8: Chat UI + Full Wire-Up

- Chat screen: bubbles, text input, voice button
- Full flow: user types → Groq → parse → route → DB + alarm/notif → confirmation in chat
- Test every intent type end-to-end
- This is where the app comes alive

### Phase 5 — Day 9: Tasks + Lists Screens

- Tasks screen: all active reminders, cancel button, mark done button
- Lists screen: movie/anime/book lists with category badges
- Task card: type label, next fire time, action buttons

### Phase 6 — Day 10: Widget + Morning Briefing

- Widget XML layout
- HomeWidget data push after every intent
- Morning briefing WorkManager job

### Phase 7 — Days 11-12: Edge Cases + Polish

- JSON parse failure retry logic
- `complete` with no matching task → graceful message
- Alarm/reminder that's already past → tell user, don't schedule
- First-launch API key screen
- Battery optimisation prompt
- App icon + name

---

## 13. Critical Gotchas

1. **WorkManager is not exact** — it fires within a window around the target time, not at a precise millisecond. Use it only for daily recurring jobs (schedules that day's notifications). For exact fire times, use `flutter_local_notifications` with exact scheduling.

2. **AlarmManager wipes on reboot** — register a `BOOT_COMPLETED` receiver. On boot, re-read all active alarms from SQLite and re-register them. Without this, all alarms disappear when the phone restarts.

3. **Android 12+ exact alarm permission** — `SCHEDULE_EXACT_ALARM` must be granted by the user in system settings. If not granted, your alarm calls silently fail. Check at launch and deep-link to the permission settings page if needed.

4. **Battery optimisation** — Moto (and most Android) aggressively kills background processes. Without whitelisting, WorkManager gets throttled or skipped. This is the most common cause of "notifications not firing." Request ignore battery optimisation at first launch. This is not optional for this app to work reliably.

5. **notification_ids must be cancelled** — every task stores its scheduled notification IDs as a JSON array in SQLite. On `complete`, loop through and cancel each one. If you skip this, ghost notifications fire forever even after the task is marked done.

6. **Chat history for context** — send the last 6 messages (3 exchanges) to Groq with every request. Without this, follow-up replies ("June 20" after "when is He-Man releasing?") are meaningless to the LLM.

7. **API key storage** — `shared_preferences`, never hardcoded in source. Show a setup screen on first launch.

---

## 14. Suggested Features After Core Works

In order of usefulness:

1. **Snooze from notification** — already wired via action buttons in the notification
2. **Voice input** — plug `speech_to_text` into the same chat flow, no extra backend needed
3. **Deadline escalation** — WorkManager checks if deadline is within 48hrs and bumps notification frequency automatically
4. **Quick-add from widget** — tap widget → opens chat via deep link intent
5. **Weekly summary** — Sunday 8pm: "Next week: 3 deadlines, CDC assessment every day"
6. **Smart default times** — learn your patterns: if you always set class alarms around 7-8am, suggest it

---

## Summary

```
User types (messy, natural)
  → Groq llama-3.1-8b-instant (JSON mode, ~1.1s)
  → {"intents": [...]}
  → intent_router loops each intent:
      alarm      → AlarmManager     → system clock, pierces DND
      reminder   → flutter_local_notifications → exact one-time
      recurring  → WorkManager      → daily job, exact notifications
      list       → SQLite           → movies/anime/books/general
      todo       → SQLite           → task with deadline
      complete   → cancel IDs + WorkManager.cancel + mark done
      query      → read SQLite      → formatted reply in chat
      clarify    → show question    → wait for follow-up

Everything local after the Groq call.
No server. No hosting. ₹0.
```
