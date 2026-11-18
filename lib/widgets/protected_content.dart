import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/vault_service.dart';
import '../utils/theme.dart';

/// Redacts an open protected editor after the app enters the background.
class ProtectedContent extends StatefulWidget {
  final bool protected;
  final Widget child;
  const ProtectedContent({Key? key, required this.protected, required this.child}) : super(key: key);

  @override
  State<ProtectedContent> createState() => _ProtectedContentState();
}

class _ProtectedContentState extends State<ProtectedContent> with WidgetsBindingObserver {
  static const _channel = MethodChannel('io.github.thelazyindian.tasks/native');
  static int _secureOwners = 0;
  bool _registeredSecure = false;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _secureWindow(widget.protected);
  }

  Future<void> _secureWindow(bool value) async {
    if (_registeredSecure == value) return;
    _registeredSecure = value;
    _secureOwners += value ? 1 : -1;
    try { await _channel.invokeMethod('setSecureWindow', {'enabled': _secureOwners > 0}); } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant ProtectedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.protected != widget.protected) _secureWindow(widget.protected);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.protected && (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)) {
      setState(() => _locked = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _secureWindow(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked || !widget.protected) return widget.child;
    return Material(
      color: googleSurface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline_rounded, size: 40, color: googleBlue),
          const SizedBox(height: 16),
          const Text('Your note is locked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Verify your PIN or tap the biometric icon to continue.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: () async {
            await VaultService.instance.showAuthDialog(context, onAuthenticated: () {
              if (mounted) setState(() => _locked = false);
            });
          }, child: const Text('Unlock note')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ]),
      )),
    );
  }
}
