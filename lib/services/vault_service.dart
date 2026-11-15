import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../data/database_service.dart';
import '../utils/theme.dart';

class VaultService {
  static final VaultService instance = VaultService._internal();
  VaultService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  String _hashPin(String pin) {
    return sha256.convert(utf8.encode(pin)).toString();
  }

  Future<bool> hasVaultPin() async {
    final hash = await DatabaseService.instance.getKeepVaultPinHash();
    return hash != null && hash.trim().isNotEmpty;
  }

  Future<bool> verifyPin(String pin) async {
    final hash = await DatabaseService.instance.getKeepVaultPinHash();
    if (hash == null || hash.trim().isEmpty) return false;
    return hash.trim() == _hashPin(pin.trim());
  }

  Future<void> setVaultPin(String pin) async {
    final hash = _hashPin(pin.trim());
    await DatabaseService.instance.setKeepVaultPinHash(hash);
  }

  Future<void> removeVaultPin() async {
    await DatabaseService.instance.removeKeepVaultPinHash();
  }

  Future<bool> isBiometricsEnabled() async {
    return await DatabaseService.instance.isKeepBiometricsEnabled();
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    await DatabaseService.instance.setKeepBiometricsEnabled(enabled);
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final canBio = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canBio || supported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics({
    String reason = 'Authenticate to access protected note',
  }) async {
    try {
      final can = await canCheckBiometrics();
      if (!can) return false;
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> showAuthDialog(
    BuildContext context, {
    String title = 'Unlock Protected Note',
    required VoidCallback onAuthenticated,
  }) async {
    final hasPin = await hasVaultPin();
    if (!hasPin) {
      // If no PIN has been set yet, prompt user to set a PIN
      if (!context.mounted) return;
      await showSetPinDialog(
        context,
        title: 'Set Master Vault PIN',
        subtitle: 'Create a 4-digit PIN to protect private notes.',
        onPinSet: onAuthenticated,
      );
      return;
    }

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VaultPinAuthSheet(
        title: title,
        onAuthenticated: onAuthenticated,
      ),
    );
  }

  Future<bool?> showSetPinDialog(
    BuildContext context, {
    String title = 'Set Master Vault PIN',
    String subtitle = 'Enter a 4-digit PIN to secure protected notes.',
    VoidCallback? onPinSet,
  }) async {
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VaultSetPinSheet(
        title: title,
        subtitle: subtitle,
        onPinSet: onPinSet,
      ),
    );
  }
}

class _VaultPinAuthSheet extends StatefulWidget {
  final String title;
  final VoidCallback onAuthenticated;

  const _VaultPinAuthSheet({
    Key? key,
    required this.title,
    required this.onAuthenticated,
  }) : super(key: key);

  @override
  _VaultPinAuthSheetState createState() => _VaultPinAuthSheetState();
}

class _VaultPinAuthSheetState extends State<_VaultPinAuthSheet> {
  String _enteredPin = '';
  String? _errorMessage;
  bool _canBio = false;

  @override
  void initState() {
    super.initState();
    _checkAndPromptBiometrics();
  }

  Future<void> _checkAndPromptBiometrics() async {
    final enabled = await VaultService.instance.isBiometricsEnabled();
    final canBio = await VaultService.instance.canCheckBiometrics();
    if (mounted) {
      setState(() => _canBio = canBio);
    }
    if (enabled && canBio) {
      final success = await VaultService.instance.authenticateWithBiometrics(
        reason: widget.title,
      );
      if (success && mounted) {
        Navigator.pop(context);
        widget.onAuthenticated();
      }
    }
  }

  void _onDigitPressed(String digit) async {
    if (_enteredPin.length >= 6) return;
    HapticFeedback.lightImpact();
    setState(() {
      _errorMessage = null;
      _enteredPin += digit;
    });

    if (_enteredPin.length >= 4) {
      final valid = await VaultService.instance.verifyPin(_enteredPin);
      if (valid) {
        HapticFeedback.mediumImpact();
        if (mounted) {
          Navigator.pop(context);
          widget.onAuthenticated();
        }
      } else if (_enteredPin.length == 4) {
        // Wait briefly in case user is entering a 6-digit PIN
        Future.delayed(const Duration(milliseconds: 300), () async {
          if (!mounted) return;
          if (_enteredPin.length == 4) {
            final checkAgain = await VaultService.instance.verifyPin(_enteredPin);
            if (!checkAgain && mounted) {
              setState(() {
                _errorMessage = 'Incorrect PIN. Try again.';
                _enteredPin = '';
              });
              HapticFeedback.heavyImpact();
            }
          }
        });
      } else if (_enteredPin.length == 6) {
        setState(() {
          _errorMessage = 'Incorrect PIN. Try again.';
          _enteredPin = '';
        });
        HapticFeedback.heavyImpact();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _errorMessage = null;
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E2EC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: googleBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded, color: googleBlue, size: 26),
              ),
              const SizedBox(height: 12),

              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: googleTextPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter Master Vault PIN to unlock',
                style: TextStyle(fontSize: 13, color: googleTextSecondary),
              ),
              const SizedBox(height: 20),

              // PIN dots indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final filled = index < _enteredPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: filled ? 16 : 14,
                    height: filled ? 16 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _errorMessage != null
                          ? googleRed
                          : filled
                              ? googleBlue
                              : const Color(0xFFE0E2EC),
                    ),
                  );
                }),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: googleRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Numeric Keypad
              _buildKeypad(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var col = 1; col <= 3; col++)
                  _buildKey('${row * 3 + col}'),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Biometric or Empty Button
              _canBio
                  ? IconButton(
                      iconSize: 28,
                      icon: const Icon(Icons.fingerprint_rounded, color: googleBlue),
                      tooltip: 'Use Biometrics',
                      onPressed: _checkAndPromptBiometrics,
                    )
                  : const SizedBox(width: 68, height: 56),

              _buildKey('0'),

              // Backspace Button
              InkWell(
                onTap: _onBackspace,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 68,
                  height: 56,
                  alignment: Alignment.center,
                  child: const Icon(Icons.backspace_outlined, size: 22, color: googleTextSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKey(String digit) {
    return InkWell(
      onTap: () => _onDigitPressed(digit),
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 68,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: googleHairline),
        ),
        alignment: Alignment.center,
        child: Text(
          digit,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: googleTextPrimary,
          ),
        ),
      ),
    );
  }
}

class _VaultSetPinSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onPinSet;

  const _VaultSetPinSheet({
    Key? key,
    required this.title,
    required this.subtitle,
    this.onPinSet,
  }) : super(key: key);

  @override
  _VaultSetPinSheetState createState() => _VaultSetPinSheetState();
}

class _VaultSetPinSheetState extends State<_VaultSetPinSheet> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _enableBiometrics = true;
  bool _canBio = false;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    VaultService.instance.canCheckBiometrics().then((can) {
      if (mounted) setState(() => _canBio = can);
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final pin = _pinController.text.trim();
    final confirm = _confirmController.text.trim();

    if (pin.length < 4) {
      setState(() => _errorMessage = 'PIN must be at least 4 digits');
      return;
    }
    if (pin != confirm) {
      setState(() => _errorMessage = 'PINs do not match');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await VaultService.instance.setVaultPin(pin);
      if (_canBio) {
        await VaultService.instance.setBiometricsEnabled(_enableBiometrics);
      }
      if (mounted) {
        Navigator.pop(context, true);
        widget.onPinSet?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E2EC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: googleBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield_outlined, color: googleBlue, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: googleTextPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // PIN Input
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Enter 4 to 6 Digit PIN',
                  counterText: '',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, color: googleBlue, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // Confirm PIN Input
              TextField(
                controller: _confirmController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Confirm PIN',
                  counterText: '',
                  prefixIcon: const Icon(Icons.lock_rounded, color: googleBlue, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),

              if (_canBio) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: googleHairline),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.fingerprint_rounded, color: googleBlue, size: 22),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Enable Fingerprint / Face Unlock',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: googleTextPrimary),
                        ),
                      ),
                      Switch(
                        value: _enableBiometrics,
                        activeColor: googleBlue,
                        onChanged: (val) => setState(() => _enableBiometrics = val),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, color: googleRed, fontWeight: FontWeight.w600),
                ),
              ],

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel', style: TextStyle(color: googleTextSecondary)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: googleBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save PIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
