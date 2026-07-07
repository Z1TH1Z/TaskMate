import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';

class ChatBubble extends StatefulWidget {
  final String text;
  final bool isUser;

  const ChatBubble({super.key, required this.text, required this.isUser});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: Offset(widget.isUser ? 0.15 : -0.15, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final screenW = MediaQuery.of(context).size.width;
    final offset = (screenW * 0.15).clamp(32.0, 80.0);
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Align(
          alignment: widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(
              top: 3, bottom: 3,
              left: widget.isUser ? offset : 14,
              right: widget.isUser ? 14 : offset,
            ),
            decoration: widget.isUser
                ? BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  )
                : BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border(
                      left: BorderSide(color: accent, width: 2),
                    ),
                  ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: widget.isUser ? _userText(accent) : _assistantText(accent),
          ),
        ),
      ),
    );
  }

  Widget _userText(Color accent) => Text(
        widget.text,
        style: TextStyle(
          color: ThemeProvider.contrastFg(accent),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.55,
        ),
      );

  Widget _assistantText(Color accent) {
    final lines = widget.text.split('\n');
    if (lines.length == 1) {
      return Text(widget.text,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14, height: 1.55));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lines.first,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14, height: 1.55)),
        const SizedBox(height: 4),
        Text(lines.skip(1).join('\n'),
            style: TextStyle(
                color: accent, fontSize: 12, height: 1.5)),
      ],
    );
  }
}
