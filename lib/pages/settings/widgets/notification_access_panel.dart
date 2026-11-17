import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../../services/notification_service.dart';
import '../../../utils/theme.dart';

class NotificationAccessPanel extends StatefulWidget {
  const NotificationAccessPanel({Key? key}) : super(key: key);
  @override
  State<NotificationAccessPanel> createState() => _NotificationAccessPanelState();
}

class _NotificationAccessPanelState extends State<NotificationAccessPanel> with WidgetsBindingObserver {
  static const _native = MethodChannel('io.github.thelazyindian.tasks/native');
  Map<String, bool>? _access;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }
  Future<void> _refresh() async {
    try {
      final result = await _native.invokeMapMethod<String, bool>('getNotificationAccess');
      if (mounted) setState(() { _access = result; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to read device settings.');
    }
  }
  Future<void> _request(String key) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final android = NotificationService.instance.flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (key == 'notifications') {
        final granted = await android?.requestNotificationsPermission();
        if (granted != true) await _native.invokeMethod('openNotificationSettings');
      } else if (key == 'exact') {
        await android?.requestExactAlarmsPermission();
      } else {
        await _native.invokeMethod('openFullScreenIntentSettings');
      }
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _error = 'Open Android settings to change this access.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: googleSurface, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Notification access', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('You control how reminders reach you.', style: TextStyle(color: googleTextSecondary)),
        if (_access == null && _error == null)
          const Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator()),
        if (_access != null) ...[
          const SizedBox(height: 12),
          _row('notifications', Icons.notifications_none_rounded, 'Notifications', 'Banners and reminder alerts'),
          _row('exact', Icons.schedule_rounded, 'Precise timing', 'Optional. Without access, alerts may arrive later.'),
          _row('fullScreen', Icons.alarm_rounded, 'Full-screen alarms', 'Optional. For reminders you set to alarm mode.'),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_error!, style: const TextStyle(color: googleRed))),
        const Divider(height: 24),
        Wrap(spacing: 12, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _access?['notifications'] == true && !_busy ? () async {
              await NotificationService.instance.showInstantNotification(
                title: 'NYRO Tasks', body: 'Your notification test is ready.');
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Test sent. Check your notification shade.')));
            } : null,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Send test'),
          ),
          TextButton(onPressed: () => _native.invokeMethod('openNotificationSettings'),
            child: const Text('Manage in Android')),
        ]),
      ]),
    );
  }
  Widget _row(String key, IconData icon, String title, String subtitle) {
    final enabled = _access?[key] == true;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
      Icon(icon, color: googleTextSecondary),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(enabled ? 'Enabled' : subtitle,
          style: TextStyle(fontSize: 12, color: enabled ? googleGreen : googleTextSecondary)),
      ])),
      const SizedBox(width: 8),
      if (enabled) const Icon(Icons.check_circle_outline_rounded, color: googleGreen, size: 22)
      else TextButton(onPressed: _busy ? null : () => _request(key), child: const Text('Enable')),
    ]));
  }
}
