import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/theme_provider.dart';
import 'core/scheduler/alarm_service.dart';
import 'widget/widget_provider.dart';
import 'screens/setup/api_key_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/tasks/tasks_screen.dart';
import 'screens/alarms/alarms_screen.dart';
import 'screens/lists/lists_screen.dart';
import 'screens/nonnegotiables/non_negotiables_screen.dart';

class TaskMateApp extends StatelessWidget {
  const TaskMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeProvider.instance,
      builder: (context, _) {
        final accent = ThemeProvider.instance.accent;
        return MaterialApp(
          title: 'TaskMate',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AppColors.background,
            colorScheme: ColorScheme.dark(
              primary: accent,
              surface: AppColors.surface,
            ),
            dividerColor: AppColors.divider,
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColors.background,
              elevation: 0,
              titleTextStyle: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
              ),
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              },
            ),
          ),
          home: const _AppEntry(),
        );
      },
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool? _hasKey;

  @override
  void initState() {
    super.initState();
    _checkKey();
    _requestPermissions();
    ThemeProvider.instance.load();
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    if (!await Permission.scheduleExactAlarm.isGranted) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  Future<void> _checkKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('groq_api_key') ?? '';
    setState(() => _hasKey = key.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasKey == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );
    }
    if (!_hasKey!) {
      return ApiKeyScreen(onKeySet: () => setState(() => _hasKey = true));
    }
    return const MainShell();
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AlarmService().reconcileFiredAlarms().then((_) =>
        AlarmService().cleanupStaleReminders()).then((_) =>
        WidgetProvider.refresh());
    }
  }

  List<Widget> get _screens => [
    const ChatScreen(),
    TasksScreen(isVisible: _currentIndex == 1),
    AlarmsScreen(isVisible: _currentIndex == 2),
    ListsScreen(isVisible: _currentIndex == 3),
    NonNegotiablesScreen(isVisible: _currentIndex == 4),
  ];

  static const _tabs = [
    (Icons.chat_bubble_outline, 'CHAT'),
    (Icons.check_box_outline_blank, 'TASKS'),
    (Icons.alarm, 'ALARMS'),
    (Icons.list, 'LISTS'),
    (Icons.bolt_outlined, 'DAILY'),
  ];

  void _onTabTap(int i) {
    if (i != _currentIndex) {
      HapticFeedback.lightImpact();
      setState(() => _currentIndex = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardOpen = mq.viewInsets.bottom > 0;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: keyboardOpen ? null : Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
          color: AppColors.background,
        ),
        padding: EdgeInsets.only(
          bottom: mq.viewPadding.bottom + 4,
        ),
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final active = _currentIndex == i;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onTabTap(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border(
                      top: BorderSide(
                        color: active ? accent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_tabs[i].$1, size: 20,
                          color: active ? accent : AppColors.textSecondary),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_tabs[i].$2,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                              color: active ? accent : AppColors.textSecondary,
                            )),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
