import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/database_service.dart';
import '../utils/theme.dart';

/// A stable accent per study context, without flashing random colors on rebuild.
class AppearanceService extends ChangeNotifier {
  AppearanceService._();
  static final instance = AppearanceService._();
  static const palette = [Color(0xFF087F83), Color(0xFF6750A4),
    Color(0xFF315DA8), Color(0xFF9A4564), Color(0xFF526B35), Color(0xFF93552A)];
  bool enabled = true;
  String _context = DateTime.now().toIso8601String().substring(0, 10);

  static Color seedColor(String context) {
    var hash = 0;
    for (final code in context.toLowerCase().trim().codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  Color colorFor(String context) => enabled ? seedColor(context) : googleBlue;
  Color get accent => colorFor(_context);
  void focus(String context) {
    if (_context == context) return;
    _context = context;
    notifyListeners();
  }
  Future<void> load() async {
    enabled = await DatabaseService.instance.getConfig('adaptive_colors') != '0';
    await _syncNative();
    notifyListeners();
  }
  Future<void> setEnabled(bool value) async {
    await DatabaseService.instance.setConfig('adaptive_colors', value ? '1' : '0');
    enabled = value;
    await _syncNative();
    notifyListeners();
  }
  Future<void> _syncNative() async {
    try {
      await const MethodChannel('io.github.thelazyindian.tasks/native')
          .invokeMethod('setAdaptiveColors', {'enabled': enabled});
    } on MissingPluginException { /* Widget previews and other platforms. */ }
  }

  ThemeData get theme {
    if (!enabled) return lightTheme;
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light)
        .copyWith(surface: googleSurface, onSurface: googleTextPrimary,
          outlineVariant: googleBorder);
    return lightTheme.copyWith(colorScheme: scheme,
      scaffoldBackgroundColor: Color.alphaBlend(accent.withValues(alpha: 0.035), Colors.white),
      floatingActionButtonTheme: lightTheme.floatingActionButtonTheme.copyWith(
        backgroundColor: scheme.primaryContainer, foregroundColor: scheme.onPrimaryContainer),
      inputDecorationTheme: lightTheme.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2))));
  }
}
