import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widget/widget_provider.dart';

class ThemeProvider extends ChangeNotifier {
  static final ThemeProvider instance = ThemeProvider._();
  ThemeProvider._();

  static const presets = <String, Color>{
    'emerald': Color(0xFF10B981),
    'blue': Color(0xFF3B82F6),
    'purple': Color(0xFF8B5CF6),
    'rose': Color(0xFFF43F5E),
    'orange': Color(0xFFF97316),
    'teal': Color(0xFF14B8A6),
    'amber': Color(0xFFF59E0B),
    'cyan': Color(0xFF06B6D4),
  };

  Color _accent = const Color(0xFF10B981);
  String _accentKey = 'emerald';

  Color get accent => _accent;
  String get accentKey => _accentKey;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _accentKey = prefs.getString('accent_color') ?? 'emerald';
    _accent = presets[_accentKey] ?? presets['emerald']!;
    notifyListeners();
  }

  Future<void> setAccent(String key) async {
    if (!presets.containsKey(key) || key == _accentKey) return;
    _accentKey = key;
    _accent = presets[key]!;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accent_color', key);
    WidgetProvider.refresh();
  }

  static Color contrastFg(Color bg) {
    return bg.computeLuminance() > 0.4
        ? const Color(0xFF0A0A0A)
        : const Color(0xFFEDEDED);
  }
}
