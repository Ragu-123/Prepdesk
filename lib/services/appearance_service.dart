import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../data/database_service.dart';
import '../utils/theme.dart';

/// A fresh, non-repeating accent per launch, stable across routes and rebuilds.
class AppearanceService extends ChangeNotifier {
  AppearanceService._();
  static final instance = AppearanceService._();
  static const palette = [Color(0xFF087F83), Color(0xFF6750A4),
    Color(0xFF315DA8), Color(0xFF9A4564), Color(0xFF526B35), Color(0xFF93552A)];
  bool enabled = true;
  int _accentIndex = 2;
  static const colorNames = ['Lagoon', 'Iris', 'Blue', 'Rose', 'Olive', 'Clay'];
  String get colorName => enabled ? colorNames[_accentIndex] : 'Blue';

  static int nextAccentIndex(int previous, Random random) {
    final next = random.nextInt(palette.length - 1);
    return next >= previous ? next + 1 : next;
  }

  Color colorFor(String _) => accent;
  Color get accent => enabled ? palette[_accentIndex] : googleBlue;
  Future<void> load({bool newSession = false}) async {
    enabled = await DatabaseService.instance.getConfig('adaptive_colors') != '0';
    final stored = int.tryParse(await DatabaseService.instance.getConfig('appearance_accent_index') ?? '');
    _accentIndex = stored != null && stored >= 0 && stored < palette.length ? stored : 2;
    if (newSession && enabled) {
      _accentIndex = nextAccentIndex(_accentIndex, Random.secure());
      await DatabaseService.instance.setConfig('appearance_accent_index', _accentIndex.toString());
    }
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
          .invokeMethod('setAdaptiveColors', {'enabled': enabled, 'accent': accent.toARGB32()});
    } on MissingPluginException { /* Widget previews and other platforms. */ }
  }

  ThemeData get theme {
    if (!enabled) return lightTheme;
    return buildLightTheme(accent);
  }
}
