import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';

class FullScreenAlarmDialog extends StatefulWidget {
  final String title;
  final String timeText;
  final VoidCallback? onSnooze5;
  final VoidCallback? onSnooze10;
  final VoidCallback? onDismiss;

  const FullScreenAlarmDialog({
    Key? key,
    required this.title,
    required this.timeText,
    this.onSnooze5,
    this.onSnooze10,
    this.onDismiss,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String timeText,
    VoidCallback? onSnooze5,
    VoidCallback? onSnooze10,
    VoidCallback? onDismiss,
  }) async {
    try {
      DatabaseService.instance.addInAppNotification(
        title: 'Alarm Ringing: $title',
        message: 'Triggered at $timeText (Full-screen alarm)',
        type: 'alarm',
      );
    } catch (_) {}

    if (!context.mounted) return;
    const native = MethodChannel('io.github.thelazyindian.tasks/native');
    try { await native.invokeMethod('setAlarmWindow', {'enabled': true}); } catch (_) {}
    if (!context.mounted) return;
    try {
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: googleBackground,
      transitionDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 240),
      pageBuilder: (ctx, anim1, anim2) => FullScreenAlarmDialog(
        title: title,
        timeText: timeText,
        onSnooze5: onSnooze5,
        onSnooze10: onSnooze10,
        onDismiss: onDismiss,
      ),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
    } finally {
      try { await native.invokeMethod('setAlarmWindow', {'enabled': false}); } catch (_) {}
    }
  }

  @override
  _FullScreenAlarmDialogState createState() => _FullScreenAlarmDialogState();
}

class _FullScreenAlarmDialogState extends State<FullScreenAlarmDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulseController.stop();
      _pulseController.value = 0;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: googleBackground,
      body: SafeArea(
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Indicator
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.alarm_rounded, color: googleTextPrimary, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Study Alarm',
                          style: TextStyle(
                            color: googleTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
              // Center: Pulsing Ring & Alarm Information
              Column(
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.transparent,
                            blurRadius: 0,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: googleTextPrimary,
                          size: 60,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  Text(
                    widget.timeText,
                    style: const TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w300,
                      color: googleTextPrimary,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: googleTextPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'NYRO GATE Study Reminder',
                    style: TextStyle(
                      fontSize: 14,
                      color: googleTextSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),
              // Bottom Actions: Snooze Options & Dismiss
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onSnooze5?.call();
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: googleBorder),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        icon: const Icon(Icons.snooze_rounded, size: 18),
                        label: const Text('Snooze 5m', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onSnooze10?.call();
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: googleBorder),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        icon: const Icon(Icons.snooze_rounded, size: 18),
                        label: const Text('Snooze 10m', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDismiss?.call();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: googleRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 22),
                      label: const Text(
                        'Dismiss Alarm',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        )),
      ),
    );
  }
}
