import 'package:flutter/material.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';

class TopBannerAction {
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  final IconData? icon;

  const TopBannerAction({
    required this.label,
    required this.onPressed,
    this.color,
    this.icon,
  });
}

class TopBanner {
  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
    Color? color,
    Duration duration = const Duration(milliseconds: 3500),
    String type = 'INFO',
    List<TopBannerAction>? actions,
    VoidCallback? onTap,
    bool logToHistory = true,
  }) {
    // Remove any currently displayed banner
    dismiss();

    if (logToHistory) {
      try {
        DatabaseService.instance.addInAppNotification(
          title: title,
          message: message,
          type: type,
        );
      } catch (_) {}
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (context) => _TopBannerWidget(
        title: title,
        message: message,
        icon: icon,
        color: color ?? Theme.of(context).colorScheme.primary,
        duration: duration,
        actions: actions,
        onTap: onTap,
        onDismiss: () => dismiss(),
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  static void showReminder(
    BuildContext context, {
    required String title,
    required String message,
    VoidCallback? onSnooze5,
    VoidCallback? onSnooze10,
    VoidCallback? onDismiss,
    VoidCallback? onTap,
  }) {
    show(
      context,
      title: title,
      message: message,
      icon: Icons.alarm_on_rounded,
      color: Theme.of(context).colorScheme.primary,
      duration: const Duration(seconds: 8),
      type: 'reminder',
      onTap: onTap,
      actions: [
        TopBannerAction(
          label: 'Snooze 5m',
          icon: Icons.snooze_rounded,
          color: Theme.of(context).colorScheme.primary,
          onPressed: () {
            onSnooze5?.call();
          },
        ),
        TopBannerAction(
          label: 'Snooze 10m',
          icon: Icons.snooze_rounded,
          color: googleAmber,
          onPressed: () {
            onSnooze10?.call();
          },
        ),
        TopBannerAction(
          label: 'Dismiss',
          icon: Icons.done_all_rounded,
          color: googleGreen,
          onPressed: () {
            onDismiss?.call();
          },
        ),
      ],
    );
  }

  static void showRoutine(
    BuildContext context, {
    required String title,
    required String message,
    VoidCallback? onView,
    VoidCallback? onSnooze,
    VoidCallback? onDismiss,
  }) {
    show(
      context,
      title: title,
      message: message,
      icon: Icons.schedule_rounded,
      color: googleAmber,
      duration: const Duration(seconds: 8),
      type: 'routine',
      actions: [
        if (onView != null)
          TopBannerAction(
            label: 'View Schedule',
            icon: Icons.calendar_today_rounded,
            color: Theme.of(context).colorScheme.primary,
            onPressed: onView,
          ),
        TopBannerAction(
          label: 'Snooze 10m',
          icon: Icons.snooze_rounded,
          color: googleAmber,
          onPressed: () {
            onSnooze?.call();
          },
        ),
        TopBannerAction(
          label: 'Dismiss',
          icon: Icons.close_rounded,
          color: googleTextSecondary,
          onPressed: () {
            onDismiss?.call();
          },
        ),
      ],
    );
  }

  static void dismiss() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _TopBannerWidget extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final Duration duration;
  final List<TopBannerAction>? actions;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _TopBannerWidget({
    Key? key,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.duration,
    this.actions,
    this.onTap,
    required this.onDismiss,
  }) : super(key: key);

  @override
  _TopBannerWidgetState createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();

    // Auto-dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismissWithAnimation();
      }
    });
  }

  void _dismissWithAnimation() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top + 8;

    return Positioned(
      top: topPadding,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offsetAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta != null && details.primaryDelta! < -4) {
                  _dismissWithAnimation();
                }
              },
              onTap: () {
                if (widget.onTap != null) {
                  widget.onTap!();
                }
                _dismissWithAnimation();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: widget.color.withOpacity(0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(color: widget.color.withOpacity(0.2), width: 1.2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(widget.icon, color: widget.color, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: googleTextPrimary,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.message,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: googleTextSecondary,
                                  height: 1.25,
                                ),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _dismissWithAnimation,
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded, size: 16, color: googleTextSecondary),
                          ),
                        ),
                      ],
                    ),
                    if (widget.actions != null && widget.actions!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1, thickness: 0.8, color: googleHairline),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: widget.actions!.map((action) {
                          final btnColor = action.color ?? widget.color;
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: InkWell(
                              onTap: () {
                                action.onPressed();
                                _dismissWithAnimation();
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: btnColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (action.icon != null) ...[
                                      Icon(action.icon, size: 14, color: btnColor),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      action.label,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: btnColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
