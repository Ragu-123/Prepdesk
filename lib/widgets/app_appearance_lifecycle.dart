import 'package:flutter/material.dart';
import '../services/appearance_service.dart';
import '../services/notification_service.dart';

/// Reopening from the background counts as a new session too.
class AppAppearanceLifecycle extends StatefulWidget {
  final Widget child;
  const AppAppearanceLifecycle({super.key, required this.child});
  @override
  State<AppAppearanceLifecycle> createState() => _AppAppearanceLifecycleState();
}

class _AppAppearanceLifecycleState extends State<AppAppearanceLifecycle> with WidgetsBindingObserver {
  bool _backgrounded = false;
  bool _refreshing = false;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _backgrounded = true;
    if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      _refresh();
    }
  }
  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await AppearanceService.instance.load(newSession: true);
      await NotificationService.instance.refreshAppearanceForSession();
    } catch (error) {
      debugPrint('Unable to refresh appearance: $error');
    } finally { _refreshing = false; }
  }
  @override
  Widget build(BuildContext context) => widget.child;
}
