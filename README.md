<p align="center">
  <img src="Assets/icon/app_icon.png" width="100" alt="TaskMate Icon" />
</p>

<h1 align="center">TaskMate</h1>

<p align="center">
  <strong>Your personal task manager that understands plain English.</strong><br/>
  Just type what you need — TaskMate handles the rest.
</p>

<p align="center">
  <a href="https://github.com/Z1TH1Z/TaskMate/releases/latest">
    <img src="https://img.shields.io/github/v/release/Z1TH1Z/TaskMate?style=flat-square&color=10B981&label=Download%20APK" alt="Download" />
  </a>
  <img src="https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Flutter-3.10+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/LLM-Groq-F55036?style=flat-square" alt="Groq" />
</p>

---

## What is TaskMate?

TaskMate is a chat-based task manager for Android. Instead of navigating menus and filling forms, you just talk to it:

> *"remind me to call mom at 6pm"*
> *"set 3 alarms before 8am"*
> *"add Inception to my movies list"*
> *"what's due today?"*

It parses your natural language using an LLM (via Groq), creates the right alarms, reminders, todos, or lists, and schedules real Android notifications that fire even when the app is closed.

---

## Features

| | Feature | Description |
|---|---|---|
| **Chat Interface** | Natural language input | Type or speak — TaskMate figures out what you mean |
| **Alarms** | Native Android alarms | Full-screen alarm with ringtone, survives reboot |
| **Reminders** | One-time notifications | Fires at the exact time you set |
| **Recurring** | Repeating notifications | Daily, weekdays, or custom schedules |
| **Todos** | Simple task tracking | With due dates and priority levels |
| **Lists** | Watchlists & reading lists | Movies, anime, books, or custom categories |
| **Voice Input** | Speech-to-text | Tap the mic and speak naturally |
| **Home Widget** | Glanceable info | Shows next alarm and today's task count |
| **Smart Scheduling** | Multi-alarm clustering | "3 alarms before 8am" spaces them intelligently |
| **Undo** | Reversible actions | Swipe to complete/delete with 4-second undo window |
| **Suggestion Chips** | Quick-reply actions | Context-aware follow-up suggestions after each response |
| **Themes** | 8 accent colors | Emerald, blue, purple, rose, orange, teal, amber, cyan |
| **Haptic Feedback** | Tactile responses | Subtle vibrations on key interactions |
| **Swipe Actions** | Bidirectional gestures | Swipe left/right for complete, delete, or mark done |

---

## How It Works

```
User message
    |
    v
Groq LLM (llama-3.1-8b-instant)
    |
    v
Intent Parser (AM/PM correction, multi-alarm expansion)
    |
    v
Intent Router --> Alarm Service (native AlarmManager)
              --> Notification Service
              --> SQLite Database
              --> Home Widget refresh
```

The LLM converts your message into structured intents (alarm, reminder, todo, list, query, etc.). The intent parser applies client-side corrections for time parsing accuracy, then the router executes each intent against the appropriate service.

---

## Getting Started

### Download

Grab the latest APK from [**Releases**](https://github.com/Z1TH1Z/TaskMate/releases/latest) and install it on your Android device.

> Requires Android 8.0+ (API 26)

### Setup

1. Get a free API key from [**console.groq.com**](https://console.groq.com/)
2. Open TaskMate and paste your key on the setup screen
3. Start chatting

### Build from Source

```bash
git clone https://github.com/Z1TH1Z/TaskMate.git
cd TaskMate
flutter pub get
flutter run
```

Requires Flutter 3.10+ and JDK 21.

---

## Try These Commands

| What you say | What happens |
|---|---|
| `set an alarm for 7am` | Creates a native alarm at 7:00 AM |
| `remind me to drink water in 30 minutes` | One-time notification 30 min from now |
| `3 alarms before my 9am meeting` | Alarms at ~8:00, 8:30, 8:45 AM |
| `remind me about assessment daily at 10am and 3pm until July 20` | Recurring notifications on weekdays |
| `add Dune to my books list` | Creates/updates a "Books" list |
| `what's due today?` | Shows today's tasks and alarms |
| `cancel it` | Cancels the most recently created item |
| `reschedule it to 5pm` | Moves the last alarm/reminder |
| `done with vit assessment` | Marks matching tasks complete |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| LLM | Groq API — llama-3.1-8b-instant |
| Database | SQLite via sqflite |
| Alarms | Native Android AlarmManager (Kotlin) |
| Notifications | flutter_local_notifications + android_alarm_manager_plus |
| Voice | speech_to_text |
| Widget | home_widget |
| State | SharedPreferences + SQLite |

---

## Project Structure

```
lib/
  app.dart                    # App shell, navigation, theme
  main.dart                   # Entry point, initialization
  core/
    db/                       # SQLite database & repositories
    llm/                      # Groq service, intent parser, system prompt
    router/                   # Intent routing to services
    scheduler/                # Alarm, notification, ringtone services
    theme/                    # Colors & theme provider
  models/                     # Data models & intent types
  screens/
    chat/                     # Chat UI, bubbles, suggestion chips
    tasks/                    # Task list with swipe actions
    alarms/                   # Alarm management
    lists/                    # Watchlists & reading lists
    settings/                 # Theme picker, alarm sound
  widget/                     # Home screen widget provider

android/
  .../kotlin/.../
    AlarmScheduler.kt         # Native alarm scheduling
    AlarmReceiver.kt          # Broadcast receiver
    AlarmActivity.kt          # Full-screen alarm UI
    AlarmForegroundService.kt # Foreground service for reliability
    TaskMateWidgetProvider.kt # Home widget with dynamic theming
```

---

## License

This project is open source. Feel free to fork, modify, and use it.

---

<p align="center">
  Built with Flutter & Groq
</p>
