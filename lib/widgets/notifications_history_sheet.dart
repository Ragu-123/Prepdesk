import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/pages/alerts/alerts_page.dart';
import 'package:tasks/pages/cloud_sync/cloud_sync_page.dart';
import 'package:tasks/pages/keep/keep_page.dart';
import 'package:tasks/utils/theme.dart';

class NotificationsHistorySheet extends StatefulWidget {
  final VoidCallback? onOpenToday;
  final VoidCallback? onRefresh;

  const NotificationsHistorySheet({
    Key? key,
    this.onOpenToday,
    this.onRefresh,
  }) : super(key: key);

  @override
  _NotificationsHistorySheetState createState() => _NotificationsHistorySheetState();
}

class _NotificationsHistorySheetState extends State<NotificationsHistorySheet> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final list = await DatabaseService.instance.getInAppNotifications();
    if (mounted) {
      setState(() {
        _notifications = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAll() async {
    await DatabaseService.instance.clearInAppNotifications();
    _loadNotifications();
  }

  void _handleNotificationTap(Map<String, dynamic> item) {
    final type = (item['type'] as String? ?? '').toLowerCase();
    Navigator.pop(context);

    if (type.contains('reminder') || type.contains('alarm')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AlertsPage(
            onDataChanged: () => widget.onRefresh?.call(),
            onOpenAddReminder: () {},
          ),
        ),
      );
    } else if (type.contains('keep')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const KeepPage()),
      );
    } else if (type.contains('cloud')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CloudSyncPage()),
      );
    } else if (type.contains('schedule') || type.contains('routine')) {
      widget.onOpenToday?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E2EC),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notifications_active_outlined, color: googleBlue, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Notifications History',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: googleTextPrimary,
                      ),
                    ),
                  ],
                ),
                if (_notifications.isNotEmpty)
                  TextButton(
                    onPressed: _clearAll,
                    child: const Text('Clear all', style: TextStyle(color: googleRed, fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 16, thickness: 1, color: googleHairline),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none_rounded, size: 48, color: googleBorder.withOpacity(0.8)),
                            const SizedBox(height: 12),
                            const Text(
                              'No recent notifications',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: googleTextSecondary),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Reminders, routines, sync logs, and study alerts will appear here.',
                              style: TextStyle(fontSize: 12, color: googleTextSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _notifications.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1, color: googleHairline),
                        itemBuilder: (context, index) {
                          final item = _notifications[index];
                          final title = item['title'] as String? ?? 'Notification';
                          final message = item['message'] as String? ?? '';
                          final type = (item['type'] as String? ?? 'INFO').toLowerCase();
                          final createdAtStr = item['created_at'] as String?;

                          DateTime? dt;
                          if (createdAtStr != null) {
                            dt = DateTime.tryParse(createdAtStr);
                          }
                          final timeDisplay = dt != null ? DateFormat('d MMM • hh:mm a').format(dt) : '';

                          IconData icon = Icons.info_outline_rounded;
                          Color color = googleBlue;

                          if (type.contains('mistake')) {
                            icon = Icons.laptop_chromebook_rounded;
                            color = googleAmber;
                          } else if (type.contains('cloud')) {
                            icon = Icons.cloud_done_outlined;
                            color = googleGreen;
                          } else if (type.contains('alarm')) {
                            icon = Icons.alarm_rounded;
                            color = googleRed;
                          } else if (type.contains('reminder')) {
                            icon = Icons.alarm_on_rounded;
                            color = googleBlue;
                          } else if (type.contains('keep')) {
                            icon = Icons.lightbulb_outline_rounded;
                            color = const Color(0xFFFBBC04);
                          } else if (type.contains('schedule') || type.contains('routine')) {
                            icon = Icons.calendar_today_rounded;
                            color = googleAmber;
                          } else if (type.contains('quiz')) {
                            icon = Icons.quiz_outlined;
                            color = Colors.deepPurple;
                          }

                          return InkWell(
                            onTap: () => _handleNotificationTap(item),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(icon, color: color, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (timeDisplay.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                timeDisplay,
                                                style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          message,
                                          style: const TextStyle(fontSize: 12, color: googleTextSecondary, height: 1.3),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
