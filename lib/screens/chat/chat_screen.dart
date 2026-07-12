import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/db/database.dart';
import '../../core/db/repositories/chat_repository.dart';
import '../../core/llm/groq_service.dart' show GroqService, GroqRateLimitException;
import '../../core/llm/intent_parser.dart';
import '../../core/llm/offline_parser.dart';
import '../../core/router/intent_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';
import '../../models/chat_message.dart';
import '../settings/settings_screen.dart';
import '../../utils/date_helper.dart';
import '../../widget/widget_provider.dart';
import 'chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _stt = SpeechToText();

  final List<_Message> _messages = [];
  bool _loading = false;
  bool _listening = false;

  late ChatRepository _chatRepo;
  late IntentRouter _router;
  late GroqService _groq;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = await DatabaseHelper.instance.database;
    _chatRepo = ChatRepository(db);
    _router = IntentRouter(db);

    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('groq_api_key') ?? '';
    _groq = GroqService(key);

    final recent = await _chatRepo.getRecent(20);
    if (mounted) {
      setState(() {
        _messages.addAll(recent.map((m) => _Message(m.content, m.role == 'user')));
        _initialized = true;
      });
      _scrollToBottom();
    }
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _loading) return;
    _ctrl.clear();
    HapticFeedback.lightImpact();

    setState(() {
      _messages.add(_Message(text, true));
      _loading = true;
    });
    _scrollToBottom();

    await _chatRepo.insert(ChatMessage(
      role: 'user',
      content: text,
      createdAt: DateHelper.nowIso(),
    ));

    try {
      final history = (await _chatRepo.getRecent(4)).map((m) => m.toGroqFormat()).toList();
      final rawIntents = await _groq.parseMessage(text, history);
      final intents = IntentParser().parse(rawIntents, text);
      final replies = await _router.route(intents);
      final reply = replies.isEmpty ? 'Done.' : replies.join('\n\n');

      await _chatRepo.insert(ChatMessage(
        role: 'assistant',
        content: reply,
        createdAt: DateHelper.nowIso(),
      ));

      await WidgetProvider.refresh();

      if (mounted) {
        setState(() {
          _messages.add(_Message(reply, false));
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      // Groq is unreachable or rate-limited — fall back to the on-device
      // parser for common phrasings so the app still works offline.
      final offline = OfflineParser.parse(text);
      if (offline.isNotEmpty) {
        try {
          final intents = IntentParser().parse(offline, text);
          final replies = await _router.route(intents);
          final body = replies.isEmpty ? 'Done.' : replies.join('\n\n');
          final reply = '⚡ Offline — handled on-device (AI unavailable).\n\n$body';

          await _chatRepo.insert(ChatMessage(
            role: 'assistant',
            content: reply,
            createdAt: DateHelper.nowIso(),
          ));
          await WidgetProvider.refresh();

          if (mounted) {
            setState(() {
              _messages.add(_Message(reply, false));
              _loading = false;
            });
            _scrollToBottom();
          }
          return;
        } catch (_) {
          // Fall through to the error message below.
        }
      }

      final msg = e is GroqRateLimitException
          ? (e.retryAfterSeconds != null
              ? 'Slow down a sec — Groq rate limit hit. Try again in ${e.retryAfterSeconds}s.'
              : 'Slow down a sec — Groq rate limit hit. Give it a few seconds and retry.')
          : _isNetworkError(e)
              ? "Can't reach the AI — check your connection. I can still handle simple commands offline like \"remind me to call mom at 6pm\" or \"set alarm at 7am\"."
              : 'Something went wrong: $e';

      await _chatRepo.insert(ChatMessage(
        role: 'assistant',
        content: msg,
        createdAt: DateHelper.nowIso(),
      ));

      if (mounted) {
        setState(() {
          _messages.add(_Message(msg, false));
          _loading = false;
        });
        _scrollToBottom();
      }
    }
  }

  bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('clientexception') ||
        s.contains('connection') ||
        s.contains('network is unreachable') ||
        s.contains('timed out');
  }

  Future<void> _toggleVoice() async {
    HapticFeedback.lightImpact();
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    final available = await _stt.initialize();
    if (!available) return;
    setState(() => _listening = true);
    await _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          _ctrl.text = result.recognizedWords;
          setState(() => _listening = false);
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  List<String> _suggestions() {
    if (_messages.isEmpty) {
      return ["What's due today?", "Set an alarm", "Add a todo", "Show my lists"];
    }
    final last = _messages.last;
    if (last.isUser || _loading) return [];
    final t = last.text.toLowerCase();

    if (t.contains('alarm') && (t.contains('set') || t.contains('✓'))) {
      return ["Show my alarms", "Cancel it", "Set another alarm"];
    }
    if (t.contains('reminder set') || t.contains('reminder —')) {
      return ["Show my tasks", "Cancel it", "Reschedule it"];
    }
    if (t.contains('todo added')) {
      return ["What's due today?", "Show my todos"];
    }
    if (t.contains('added to') || t.contains('removed from')) {
      return ["Show the list", "Add more items"];
    }
    if (t.contains("here's what")) {
      return ["Done for today", "Clear all alarms"];
    }
    if (t.contains('rescheduled')) {
      return ["Show my tasks", "Show my alarms"];
    }
    if (t.contains('marked done') || t.contains('cancelled')) {
      return ["What's left?", "Show my tasks"];
    }
    return ["What's due today?", "Set an alarm", "Show my tasks"];
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardOpen = mq.viewInsets.bottom > 0;
    final landscape = mq.orientation == Orientation.landscape;
    final showHeader = !(keyboardOpen && landscape);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: showHeader ? _header() : const SizedBox.shrink(),
            ),
            Expanded(child: _body()),
            _suggestionChips(),
            _inputBar(keyboardOpen),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          const Text('TaskMate',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              )),
          const Spacer(),
          Container(width: 6, height: 6, color: accent),
          const SizedBox(width: 5),
          const Text('Groq',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: const Icon(Icons.settings_outlined,
                size: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (!_initialized) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    if (_messages.isEmpty) return _emptyState();
    return ListView.builder(
      controller: _scrollCtrl,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _messages.length) return const _TypingIndicator();
        final m = _messages[i];
        return ChatBubble(text: m.text, isUser: m.isUser);
      },
    );
  }

  Widget _emptyState() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: AnimatedOpacity(
              opacity: _initialized ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 40, color: AppColors.textSecondary),
                  SizedBox(height: 14),
                  Text('What do you need to remember?',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  SizedBox(height: 6),
                  Text('"remind me to call mom at 6pm"',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestionChips() {
    final chips = _suggestions();
    if (chips.isEmpty) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _send(chips[i]);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
            ),
            child: Text(chips[i],
                style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  Widget _inputBar(bool keyboardOpen) {
    final bottomPad = keyboardOpen ? 6.0 : 6.0 + MediaQuery.of(context).viewPadding.bottom;
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(14, 10, 14, bottomPad),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: _listening ? 'Listening...' : 'type anything...',
                  hintStyle:
                      const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _toggleVoice,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _listening ? Icons.mic : Icons.mic_none,
                  key: ValueKey(_listening),
                  color: _listening ? AppColors.alarm : accent,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _loading ? null : () => _send(_ctrl.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _loading ? AppColors.textSecondary : accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.arrow_upward,
                    color: ThemeProvider.contrastFg(accent), size: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message {
  final String text;
  final bool isUser;
  _Message(this.text, this.isUser);
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 14, top: 4, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(delay: 0),
            SizedBox(width: 4),
            _Dot(delay: 150),
            SizedBox(width: 4),
            _Dot(delay: 300),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _anim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => Opacity(
        opacity: 0.3 + _anim.value * 0.7,
        child: Container(
          width: 5, height: 5,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }
}
