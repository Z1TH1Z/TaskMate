import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/scheduler/ringtone_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _ringtone = RingtoneService();
  String? _soundTitle;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final title = await _ringtone.currentTitle();
    if (mounted) {
      setState(() {
        _soundTitle = title;
        _loading = false;
      });
    }
  }

  Future<void> _pick() async {
    final title = await _ringtone.pickRingtone();
    if (title != null && mounted) {
      setState(() => _soundTitle = title);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alarm sound set to "$title"')),
      );
    }
  }

  Future<void> _reset() async {
    await _ringtone.resetToDefault();
    if (mounted) setState(() => _soundTitle = null);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: accent))
          : ListView(
              children: [
                _sectionLabel('THEME'),
                _accentPicker(accent),
                const SizedBox(height: 8),
                _sectionLabel('ALARM'),
                _tile(
                  icon: Icons.music_note_outlined,
                  title: 'Alarm sound',
                  subtitle: _soundTitle ?? 'Default alarm sound',
                  onTap: _pick,
                  accent: accent,
                ),
                _tile(
                  icon: Icons.play_circle_outline,
                  title: 'Test alarm sound',
                  subtitle: 'Play the selected sound once',
                  onTap: () => _ringtone.playPreview(),
                  accent: accent,
                ),
                if (_soundTitle != null)
                  _tile(
                    icon: Icons.restart_alt,
                    title: 'Reset to default',
                    subtitle: 'Use the system alarm sound',
                    onTap: _reset,
                    accent: accent,
                  ),
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    'Alarms ring once with vibration. Pick any sound on your '
                    'device — ringtones, notification tones, or music you\'ve '
                    'added.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11, height: 1.5),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _accentPicker(Color currentAccent) {
    final provider = ThemeProvider.instance;
    final selected = provider.accentKey;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: ThemeProvider.presets.entries.map((e) {
          final isSelected = e.key == selected;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              provider.setAccent(e.key);
              setState(() {});
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: e.value,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: AppColors.textPrimary, width: 2.5)
                    : null,
                boxShadow: isSelected
                    ? [BoxShadow(color: e.value.withValues(alpha: 0.4), blurRadius: 8)]
                    : null,
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 16, color: ThemeProvider.contrastFg(e.value))
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Text(text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            )),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color accent,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
