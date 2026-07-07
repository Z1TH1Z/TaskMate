import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/scheduler/workmanager_service.dart';
import '../../core/theme/app_colors.dart';

class ApiKeyScreen extends StatefulWidget {
  final VoidCallback onKeySet;
  const ApiKeyScreen({super.key, required this.onKeySet});

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  final _ctrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  Future<void> _save() async {
    final key = _ctrl.text.trim();
    if (key.isEmpty) return;
    setState(() => _saving = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('groq_api_key', key);
    await _requestPermissions(prefs);

    if (mounted) {
      setState(() => _saving = false);
      widget.onKeySet();
    }
  }

  Future<void> _requestPermissions(SharedPreferences prefs) async {
    await Permission.notification.request();
    if (!await Permission.scheduleExactAlarm.isGranted) {
      await openAppSettings();
    }
    await Permission.ignoreBatteryOptimizations.request();
    await Permission.microphone.request();
    if (!(prefs.getBool('first_launch_done') ?? false)) {
      await WorkmanagerService().registerMorningBriefing();
      await prefs.setBool('first_launch_done', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text('TaskMate',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                  )),
              const SizedBox(height: 6),
              const Text('Enter your Groq API key to get started.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 32),
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        obscureText: _obscure,
                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'gsk_...',
                          hintStyle: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _obscure = !_obscure),
                      child: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondary,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  width: double.infinity,
                  color: _saving ? AppColors.textSecondary : AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  alignment: Alignment.center,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentFg),
                        )
                      : const Text('Continue',
                          style: TextStyle(
                            color: AppColors.accentFg,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          )),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Get your free key at console.groq.com',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
