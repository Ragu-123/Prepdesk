import 'package:flutter/material.dart';
import '../../services/appearance_service.dart';
import '../../services/notification_service.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});
  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  bool _saving = false;

  Future<void> _change(bool enabled) async {
    setState(() => _saving = true);
    try {
      await AppearanceService.instance.setEnabled(enabled);
      await NotificationService.instance.refreshNotificationAppearance();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not finish applying the theme. Please retry.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppearanceService.instance, builder: (context, _) {
      final appearance = AppearanceService.instance;
      final colors = Theme.of(context).colorScheme;
      return Scaffold(appBar: AppBar(title: const Text('Appearance')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Color theme', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('One accent throughout your workspace.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          Card(margin: EdgeInsets.zero, elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: colors.outlineVariant)),
            child: Column(children: [
              SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                secondary: Icon(Icons.palette_outlined, color: colors.primary),
                title: const Text('Adaptive colors'),
                subtitle: const Text('A different accent each time you open Prepdesk.'),
                value: appearance.enabled, onChanged: _saving ? null : _change),
              Divider(height: 1, indent: 20, endIndent: 20, color: colors.outlineVariant),
              ListTile(contentPadding: const EdgeInsets.all(20),
                leading: Semantics(label: '${appearance.colorName} accent', child: Container(
                  width: 44, height: 44, decoration: BoxDecoration(color: colors.primary,
                    borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.check_rounded, color: colors.onPrimary))),
                title: const Text('Current accent'), subtitle: Text(appearance.colorName)),
            ])),
          const SizedBox(height: 20),
          Text(appearance.enabled
              ? 'Your accent stays the same while you use the app. Buttons, forms, calendars, desktop and notifications all follow it.'
              : 'The fixed blue theme is used throughout the app and notifications.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          if (_saving) const Padding(padding: EdgeInsets.only(top: 20), child: LinearProgressIndicator()),
        ]));
    });
}
