import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/data/keep_note_model.dart';
import 'package:tasks/pages/keep/note_editor_sheet.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/services/vault_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/full_screen_alarm_dialog.dart';
import 'package:tasks/widgets/google_checkbox.dart';
import 'package:tasks/widgets/top_banner_notification.dart';

class AlertsPage extends StatefulWidget {
  final VoidCallback onDataChanged;
  final VoidCallback onOpenAddReminder;

  const AlertsPage({
    Key? key,
    required this.onDataChanged,
    required this.onOpenAddReminder,
  }) : super(key: key);

  @override
  _AlertsPageState createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  List<Map<String, dynamic>> _reminders = [];
  List<KeepNote> _keepReminders = [];
  bool _isLoading = true;
  bool _isCompletedExpanded = false;
  int _activeTab = 0; // 0: Study Reminders, 1: Keep Note Reminders

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    try {
      // 1. Automatically complete expired past reminders
      await DatabaseService.instance.autoCompleteExpiredReminders();

      // 2. Load latest custom reminders
      final reminders = await DatabaseService.instance.getCustomReminders();

      // 3. Load Keep Notes with active reminders
      final keepNotes = await DatabaseService.instance.getKeepNotesWithReminders();

      if (mounted) {
        setState(() {
          _reminders = reminders;
          _keepReminders = keepNotes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading reminders: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteReminder(int id) async {
    await DatabaseService.instance.deleteCustomReminder(id);
    await NotificationService.instance.cancelNotification(id);
    await _loadAlerts();
    widget.onDataChanged();
    if (mounted) {
      TopBanner.show(
        context,
        title: 'Reminder Deleted',
        message: 'Scheduled reminder removed.',
        icon: Icons.delete_outline_rounded,
        color: googleRed,
      );
    }
  }

  Future<void> _toggleReminder(
    int id,
    bool completed, {
    String? repeatDays,
    String? remindAtStr,
    String? text,
    String alertType = 'notification',
  }) async {
    await DatabaseService.instance.toggleReminderStatus(id, completed);
    if (completed) {
      await NotificationService.instance.cancelReminder(id);
    } else if (remindAtStr != null && text != null) {
      final dt = DateTime.tryParse(remindAtStr) ?? DateTime.now();
      final reminder = _reminders.firstWhere((row) => row['id'] == id, orElse: () => <String, dynamic>{});
      List<String> checkpoints = [];
      try { checkpoints = (jsonDecode(reminder['checkpoints_json']?.toString() ?? '[]') as List).map((v) => v.toString()).toList(); } catch (_) {}
      await NotificationService.instance.scheduleReminder(
        id: id,
        title: 'Study Reminder',
        body: text,
        scheduledDate: dt,
        repeatDays: repeatDays,
        alertType: alertType,
        checkpoints: checkpoints,
      );
    }
    await _loadAlerts();
    widget.onDataChanged();
    if (mounted) {
      TopBanner.show(
        context,
        title: completed ? 'Reminder Completed' : 'Reminder Active',
        message: completed ? 'Moved to completed schedule' : 'Restored to active reminders',
        icon: completed ? Icons.task_alt_rounded : Icons.alarm_on_rounded,
        color: completed ? googleGreen : googleBlue,
      );
    }
  }

  Future<void> _openNewReminderEditor() async {
    final now = DateTime.now();
    final initialDate = now.add(const Duration(minutes: 30));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReminderEditorSheet(
        id: null,
        initialText: 'Study Reminder',
        initialDateTime: initialDate,
        initialRepeatDays: null,
        initialAlertType: 'notification',
        initialCheckpoints: const [],
        onSave: (newText, newDateTime, newRepeatDays, alertType, checkpoints) async {
          final id = await DatabaseService.instance.addCustomReminder(
            newText,
            newDateTime,
            repeatDays: newRepeatDays,
            alertType: alertType,
            checkpoints: checkpoints,
          );
          await NotificationService.instance.scheduleReminder(
            id: id,
            title: 'Study Reminder',
            body: newText,
            scheduledDate: newDateTime,
            repeatDays: newRepeatDays,
            alertType: alertType,
            checkpoints: checkpoints,
          );
          await _loadAlerts();
          widget.onDataChanged();
          if (mounted) {
            TopBanner.showReminder(
              context,
              title: alertType == 'alarm' ? 'Alarm Scheduled' : 'Reminder Scheduled',
              message: '$newText • ${DateFormat('d MMM, hh:mm a').format(newDateTime)}',
              onSnooze5: () async {
                final snoozeTime = DateTime.now().add(const Duration(minutes: 5));
                await NotificationService.instance.scheduleReminder(
                  id: DateTime.now().millisecondsSinceEpoch % 100000,
                  title: newText,
                  body: 'Snoozed: $newText',
                  scheduledDate: snoozeTime,
                  alertType: alertType,
                );
                TopBanner.show(
                  context,
                  title: 'Reminder Snoozed',
                  message: 'Will alert again in 5 minutes.',
                  icon: Icons.snooze_rounded,
                  color: googleBlue,
                );
              },
              onSnooze10: () async {
                final snoozeTime = DateTime.now().add(const Duration(minutes: 10));
                await NotificationService.instance.scheduleReminder(
                  id: DateTime.now().millisecondsSinceEpoch % 100000,
                  title: newText,
                  body: 'Snoozed: $newText',
                  scheduledDate: snoozeTime,
                  alertType: alertType,
                );
                TopBanner.show(
                  context,
                  title: 'Reminder Snoozed',
                  message: 'Will alert again in 10 minutes.',
                  icon: Icons.snooze_rounded,
                  color: googleAmber,
                );
              },
              onDismiss: () {},
            );
          }
        },
        onDelete: null,
      ),
    );
  }

  Future<void> _openReminderEditor(Map<String, dynamic> reminder) async {
    final int id = reminder['id'] as int;
    final String initialText = reminder['text'] ?? 'Study Reminder';
    final String remindAtStr = reminder['remind_at'] ?? DateTime.now().toIso8601String();
    final DateTime initialDate = DateTime.tryParse(remindAtStr) ?? DateTime.now();
    final String? repeatDays = reminder['repeat_days'] as String?;
    final String alertType = reminder['alert_type'] ?? 'notification';

    List<String> checkpoints = [];
    if (reminder['checkpoints_json'] != null) {
      try {
        final decoded = jsonDecode(reminder['checkpoints_json']);
        if (decoded is List) {
          checkpoints = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReminderEditorSheet(
        id: id,
        initialText: initialText,
        initialDateTime: initialDate,
        initialRepeatDays: repeatDays,
        initialAlertType: alertType,
        initialCheckpoints: checkpoints,
        onSave: (newText, newDateTime, newRepeatDays, newAlertType, newCheckpoints) async {
          await DatabaseService.instance.updateCustomReminder(
            id: id,
            text: newText,
            remindAt: newDateTime,
            repeatDays: newRepeatDays,
            alertType: newAlertType,
            checkpoints: newCheckpoints,
          );
          await NotificationService.instance.scheduleReminder(
            id: id,
            title: 'Study Reminder',
            body: newText,
            scheduledDate: newDateTime,
            repeatDays: newRepeatDays,
            alertType: newAlertType,
            checkpoints: newCheckpoints,
          );
          await _loadAlerts();
          widget.onDataChanged();
          if (mounted) {
            TopBanner.show(
              context,
              title: newAlertType == 'alarm' ? 'Alarm Saved' : 'Reminder Saved',
              message: '$newText • ${DateFormat('d MMM, hh:mm a').format(newDateTime)}',
              icon: Icons.alarm_on_rounded,
              color: googleGreen,
            );
          }
        },
        onDelete: () => _deleteReminder(id),
      ),
    );
  }

  void _openKeepNoteEditor(KeepNote note) {
    if (note.isLocked) {
      VaultService.instance.showAuthDialog(
        context,
        title: 'Unlock Protected Note',
        onAuthenticated: () {
          _showNoteEditorModal(note);
        },
      );
    } else {
      _showNoteEditorModal(note);
    }
  }

  void _showNoteEditorModal(KeepNote note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NoteEditorSheet(
        note: note,
        onSave: (_) => _loadAlerts(),
        onDelete: () => _loadAlerts(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _reminders.where((r) => (r['status'] as String?)?.toUpperCase() != 'COMPLETED').toList();
    final completed = _reminders.where((r) => (r['status'] as String?)?.toUpperCase() == 'COMPLETED').toList();

    return Scaffold(
      backgroundColor: googleBackground,
      appBar: AppBar(
        backgroundColor: googleBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: googleTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Reminders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: googleTextPrimary,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alarm_rounded, color: googleBlue),
            tooltip: 'Add Reminder',
            onPressed: _openNewReminderEditor,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs: Study Reminders | Keep Note Reminders
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _activeTab = 0),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _activeTab == 0 ? googleBlue.withOpacity(0.12) : const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Study Reminders (${pending.length})',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: _activeTab == 0 ? googleBlue : googleTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _activeTab = 1),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _activeTab == 1 ? googleBlue.withOpacity(0.12) : const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Keep Notes (${_keepReminders.length})',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: _activeTab == 1 ? googleBlue : googleTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          // Main Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : _activeTab == 0
                    ? _buildStudyRemindersTab(pending, completed)
                    : _buildKeepRemindersTab(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: googleBlue,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add Reminder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        onPressed: _openNewReminderEditor,
      ),
    );
  }

  Widget _buildStudyRemindersTab(List<Map<String, dynamic>> pending, List<Map<String, dynamic>> completed) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        // 1. Reminders Header
        _buildRemindersHeader(pending.length),

        // 2. Reminders List or Empty Indicator
        if (pending.isNotEmpty) ...[
          ...pending.map((r) => _buildReminderCard(r, isCompleted: false)),
        ] else if (completed.isNotEmpty) ...[
          _buildAllCompletedCard(),
        ] else ...[
          _buildEmptyReminders(),
        ],

        // 3. Completed Section Accordion
        if (completed.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _isCompletedExpanded = !_isCompletedExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _isCompletedExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                    size: 20,
                    color: googleTextSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Completed (${completed.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: googleTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isCompletedExpanded)
            ...completed.map((r) => _buildReminderCard(r, isCompleted: true)),
        ],
      ],
    );
  }

  Widget _buildKeepRemindersTab() {
    if (_keepReminders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: googleBlue.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lightbulb_outline_rounded, color: googleBlue, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Keep Note Reminders',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Add reminders to your Keep notes to have them appear here automatically with one-tap access.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: googleTextSecondary, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: _keepReminders.length,
      itemBuilder: (context, idx) {
        final note = _keepReminders[idx];
        final dt = note.reminderAt != null ? DateTime.fromMillisecondsSinceEpoch(note.reminderAt!) : null;
        final timeFormatted = dt != null ? DateFormat('h:mm a').format(dt).toLowerCase() : '';
        final dateFormatted = dt != null ? DateFormat('EEE, d MMM').format(dt) : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: googleHairline),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openKeepNoteEditor(note),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBC04).withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: Color(0xFFB06000), size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  note.isLocked
                                      ? 'Protected Note'
                                      : (note.title.isNotEmpty ? note.title : 'Untitled Note'),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: note.isLocked ? googleTextSecondary : googleTextPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (note.isLocked)
                                const Icon(Icons.lock_rounded, size: 16, color: googleBlue),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (!note.isLocked && note.content.isNotEmpty)
                            Text(
                              note.content,
                              style: const TextStyle(fontSize: 12.5, color: googleTextSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: googleBlue.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.alarm_rounded, size: 13, color: googleBlue),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$dateFormatted • $timeFormatted',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: googleBlue),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              const Text(
                                'Open Note',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue),
                              ),
                              const Icon(Icons.chevron_right_rounded, size: 16, color: googleBlue),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRemindersHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text(
                'Active Study Reminders',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: googleTextSecondary,
                  letterSpacing: 0.2,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: googleBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: googleBlue,
                    ),
                  ),
                ),
              ],
            ],
          ),
          TextButton.icon(
            onPressed: _openNewReminderEditor,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            icon: const Icon(Icons.add, size: 16, color: googleBlue),
            label: const Text(
              'New Reminder',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyReminders() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: googleBlue.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.alarm_off_outlined, color: googleBlue, size: 28),
            ),
            const SizedBox(height: 12),
            const Text(
              'No Reminders Scheduled',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Add custom reminders or alarms for revision topics, mock tests, or study blocks.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: googleTextSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openNewReminderEditor,
              icon: const Icon(Icons.add_alarm_rounded, size: 16, color: googleBlue),
              label: const Text('Add Reminder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: googleBlue)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: googleBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllCompletedCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: googleGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.task_alt_rounded, color: googleGreen, size: 24),
            ),
            const SizedBox(height: 10),
            const Text(
              'All Reminders Completed',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: googleTextPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'All active reminders have been cleared or expired into completed.',
              style: TextStyle(fontSize: 12, color: googleTextSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderCard(Map<String, dynamic> reminder, {required bool isCompleted}) {
    final id = reminder['id'] as int;
    final text = reminder['text'] ?? 'Study Reminder';
    final remindAtStr = reminder['remind_at'] ?? '';
    final String? repeatDays = reminder['repeat_days'] as String?;
    final String alertType = reminder['alert_type'] ?? 'notification';

    List<String> checkpoints = [];
    if (reminder['checkpoints_json'] != null) {
      try {
        final decoded = jsonDecode(reminder['checkpoints_json']);
        if (decoded is List) {
          checkpoints = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    DateTime remindAt = DateTime.now();
    try {
      remindAt = DateTime.parse(remindAtStr);
    } catch (_) {}

    final timeFormatted = DateFormat('h:mm a').format(remindAt).toLowerCase();
    final dateFormatted = DateFormat('EEE, d MMM').format(remindAt);

    // Compute recurring routine label if days are configured
    String routineBadgeText = 'Once';
    if (repeatDays != null && repeatDays.trim().isNotEmpty) {
      final days = repeatDays
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .where((d) => d >= 0 && d <= 6)
          .toSet();
      if (days.length == 7) {
        routineBadgeText = 'Daily';
      } else if (days.length == 5 && {1, 2, 3, 4, 5}.every(days.contains)) {
        routineBadgeText = 'Mon-Fri';
      } else if (days.length == 2 && {0, 6}.every(days.contains)) {
        routineBadgeText = 'Weekends';
      } else if (days.isNotEmpty) {
        const shortNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final sorted = days.toList()..sort();
        routineBadgeText = sorted.map((d) => shortNames[d]).join(', ');
      }
    }

    final isAlarm = alertType == 'alarm';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openReminderEditor(reminder),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Completed Checkbox
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: GoogleCheckbox(
                    value: isCompleted,
                    onChanged: (val) => _toggleReminder(
                      id,
                      val,
                      repeatDays: repeatDays,
                      remindAtStr: remindAtStr,
                      text: text,
                      alertType: alertType,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Note (Title) & Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isCompleted ? googleTextSecondary : googleTextPrimary,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // Time, Repeat badge, Alert Type badge
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAlarm ? Icons.alarm_rounded : Icons.access_time_rounded,
                                size: 14,
                                color: isCompleted ? googleBorder : (isAlarm ? googleRed : googleBlue),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeFormatted,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isCompleted ? googleTextSecondary : (isAlarm ? googleRed : googleBlue),
                                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCompleted
                                  ? const Color(0xFFF1F3F4)
                                  : googleBlue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              routineBadgeText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isCompleted ? googleBorder : googleBlue,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isAlarm ? const Color(0xFFFEE2E2) : const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isAlarm ? 'Full Alarm' : 'Notification',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isAlarm ? googleRed : googleBlue,
                              ),
                            ),
                          ),
                          if (routineBadgeText == 'Once')
                            Text(
                              dateFormatted,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isCompleted ? googleBorder : googleTextSecondary,
                              ),
                            ),
                        ],
                      ),

                      // Checkpoints chip row if configured
                      if (checkpoints.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: checkpoints.map((cp) {
                            final cpDt = DateTime.tryParse(cp);
                            final cpTime = cpDt != null ? DateFormat('h:mm a').format(cpDt).toLowerCase() : cp;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F3F4),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+ $cpTime',
                                style: const TextStyle(fontSize: 10.5, color: googleTextSecondary),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Options button
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, color: googleTextSecondary, size: 20),
                  tooltip: 'Options',
                  onPressed: () => _openReminderEditor(reminder),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Google Clock / Material Style Bottom Sheet Reminder Editor
class _ReminderEditorSheet extends StatefulWidget {
  final int? id;
  final String initialText;
  final DateTime initialDateTime;
  final String? initialRepeatDays;
  final String initialAlertType;
  final List<String> initialCheckpoints;
  final Future<void> Function(
    String newText,
    DateTime newDateTime,
    String? newRepeatDays,
    String alertType,
    List<String> checkpoints,
  ) onSave;
  final VoidCallback? onDelete;

  const _ReminderEditorSheet({
    Key? key,
    this.id,
    required this.initialText,
    required this.initialDateTime,
    this.initialRepeatDays,
    this.initialAlertType = 'notification',
    this.initialCheckpoints = const [],
    required this.onSave,
    this.onDelete,
  }) : super(key: key);

  @override
  __ReminderEditorSheetState createState() => __ReminderEditorSheetState();
}

class __ReminderEditorSheetState extends State<_ReminderEditorSheet> {
  late TextEditingController _nameController;
  late TimeOfDay _selectedTime;
  late DateTime _selectedDate;
  late String _alertType; // 'notification' or 'alarm'
  late List<String> _checkpoints;
  bool _vibrate = true;
  bool _isSaving = false;
  bool _isOnce = true;

  final Set<int> _selectedDays = {};
  final List<String> _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialText);
    _selectedTime = TimeOfDay.fromDateTime(widget.initialDateTime);
    _selectedDate = widget.initialDateTime;
    _alertType = widget.initialAlertType;
    _checkpoints = List<String>.from(widget.initialCheckpoints);

    if (widget.initialRepeatDays != null && widget.initialRepeatDays!.trim().isNotEmpty) {
      final days = widget.initialRepeatDays!
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .where((d) => d >= 0 && d <= 6);
      _selectedDays.addAll(days);
      _isOnce = _selectedDays.isEmpty;
    } else {
      _isOnce = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: googleBlue,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: googleTextPrimary,
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: googleBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: googleTextPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _addCheckpoint() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select Checkpoint Date',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Select Checkpoint Time',
    );
    if (pickedTime != null && mounted) {
      final dt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      setState(() {
        _checkpoints.add(dt.toIso8601String());
      });
    }
  }

  String _formatUpcomingMessage() {
    final now = DateTime.now();
    final target = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    if (!_isOnce && _selectedDays.isNotEmpty) {
      if (_selectedDays.length == 7) {
        return 'Repeats daily at ${_formatTimeDisplay()}';
      }
      final weekdays = {1, 2, 3, 4, 5};
      final weekends = {0, 6};
      if (_selectedDays.length == 5 && weekdays.every(_selectedDays.contains)) {
        return 'Repeats weekdays (Mon-Fri) at ${_formatTimeDisplay()}';
      }
      if (_selectedDays.length == 2 && weekends.every(_selectedDays.contains)) {
        return 'Repeats weekends at ${_formatTimeDisplay()}';
      }
      const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      final sorted = _selectedDays.toList()..sort();
      final dayNames = sorted.map((d) => names[d]).join(', ');
      return 'Repeats $dayNames at ${_formatTimeDisplay()}';
    }

    if (target.isBefore(now)) {
      return 'Past time. Set a future time';
    }

    final diff = target.difference(now);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;

    if (hours == 0 && mins < 60) {
      return 'Upcoming in $mins minute${mins == 1 ? "" : "s"}';
    } else if (hours < 24 && target.day == now.day) {
      return 'Upcoming today at ${_formatTimeDisplay()}';
    } else if (hours < 48 && target.day == now.day + 1) {
      return 'Upcoming tomorrow at ${_formatTimeDisplay()}';
    } else {
      return 'Scheduled for ${DateFormat('EEE, d MMM • h:mm a').format(target)}';
    }
  }

  String _formatTimeDisplay() {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, _selectedTime.hour, _selectedTime.minute);
    return DateFormat('h:mm a').format(dt).toLowerCase();
  }

  Future<void> _handleSave() async {
    final newText = _nameController.text.trim().isEmpty ? 'Study Reminder' : _nameController.text.trim();
    final newDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final sortedDays = _selectedDays.toList()..sort();
    final String? newRepeatDays = (!_isOnce && sortedDays.isNotEmpty) ? sortedDays.join(',') : null;

    setState(() => _isSaving = true);
    try {
      await widget.onSave(newText, newDateTime, newRepeatDays, _alertType, _checkpoints);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving reminder: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        TopBanner.show(
          context,
          title: 'Error Saving Reminder',
          message: e.toString(),
          icon: Icons.error_outline_rounded,
          color: googleRed,
        );
      }
    }
  }

  void _previewAlarm() {
    FullScreenAlarmDialog.show(
      context,
      title: _nameController.text.trim().isEmpty ? 'Study Reminder' : _nameController.text.trim(),
      timeText: _formatTimeDisplay(),
      onSnooze5: () {
        TopBanner.show(
          context,
          title: 'Alarm Snoozed',
          message: 'Snoozed for 5 minutes.',
          icon: Icons.snooze_rounded,
          color: googleBlue,
        );
      },
      onSnooze10: () {
        TopBanner.show(
          context,
          title: 'Alarm Snoozed',
          message: 'Snoozed for 10 minutes.',
          icon: Icons.snooze_rounded,
          color: googleAmber,
        );
      },
      onDismiss: () {
        TopBanner.show(
          context,
          title: 'Alarm Dismissed',
          message: 'Alarm stopped successfully.',
          icon: Icons.done_all_rounded,
          color: googleGreen,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTimeDisplay();
    final upcomingMsg = _formatUpcomingMessage();

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
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
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

              // 1. Time Display with Edit Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickTime,
                    child: Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w400,
                        color: googleTextPrimary,
                        letterSpacing: -1.5,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: _pickTime,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: googleBlue,
                          side: const BorderSide(color: googleBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        ),
                        child: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline_rounded, color: googleBlue, size: 26),
                        tooltip: 'Preview Alarm Screen',
                        onPressed: _previewAlarm,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Alert Type Selector: Notification Banner vs Full-Screen Alarm
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _alertType = 'notification'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _alertType == 'notification' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _alertType == 'notification'
                                ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 16,
                                color: _alertType == 'notification' ? googleBlue : googleTextSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Notification Banner',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _alertType == 'notification' ? googleBlue : googleTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _alertType = 'alarm'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _alertType == 'alarm' ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _alertType == 'alarm'
                                ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.alarm_rounded,
                                size: 16,
                                color: _alertType == 'alarm' ? googleRed : googleTextSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Full-screen Alarm',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _alertType == 'alarm' ? googleRed : googleTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Repeat Mode: [ Once ] pill + Day Selector Pills (S M T W T F S)
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isOnce = true;
                        _selectedDays.clear();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _isOnce ? googleBlue : const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Once',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _isOnce ? Colors.white : googleTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final isSelected = !_isOnce && _selectedDays.contains(index);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _isOnce = false;
                              if (_selectedDays.contains(index)) {
                                _selectedDays.remove(index);
                                if (_selectedDays.isEmpty) {
                                  _isOnce = true;
                                }
                              } else {
                                _selectedDays.add(index);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected ? googleBlue : const Color(0xFFF1F3F4),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _dayLabels[index],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : googleTextSecondary,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 4. Upcoming Alarm Info & Calendar Pick
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          !_isOnce ? Icons.repeat_rounded : Icons.access_time_rounded,
                          size: 16,
                          color: googleTextSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            upcomingMsg,
                            style: const TextStyle(fontSize: 12, color: googleTextSecondary, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 14, color: googleBlue),
                    label: const Text('Schedule Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 5. Multiple Checkpoints / Reminders for Single Task
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: googleHairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.more_time_rounded, size: 18, color: googleBlue),
                            SizedBox(width: 8),
                            Text(
                              'Multiple Reminders for this Task',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: _addCheckpoint,
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Text(
                              '+ Add Time',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_checkpoints.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _checkpoints.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final cpStr = entry.value;
                          final cpDt = DateTime.tryParse(cpStr);
                          String label = cpStr;
                          if (cpDt != null) {
                            final isSameDay = cpDt.year == _selectedDate.year &&
                                cpDt.month == _selectedDate.month &&
                                cpDt.day == _selectedDate.day;
                            label = isSameDay
                                ? DateFormat('h:mm a').format(cpDt).toLowerCase()
                                : DateFormat('d MMM • h:mm a').format(cpDt).toLowerCase();
                          }
                          return Chip(
                            backgroundColor: googleBackground,
                            side: const BorderSide(color: googleBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() {
                                _checkpoints.removeAt(idx);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 6. Reminder Name & Vibrate
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: googleHairline),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.label_outline_rounded, size: 20, color: googleTextSecondary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: googleTextPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Reminder name (e.g. GATE Revision)',
                                border: InputBorder.none,
                                hintStyle: TextStyle(fontSize: 13, color: googleBorder),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 1, color: googleHairline),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.vibration_rounded, size: 20, color: googleTextSecondary),
                          const SizedBox(width: 14),
                          const Text('Vibrate', style: TextStyle(fontSize: 14, color: googleTextPrimary)),
                          const Spacer(),
                          Switch(
                            value: _vibrate,
                            activeColor: googleBlue,
                            onChanged: (val) => setState(() => _vibrate = val),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 7. Actions: Delete / Cancel (Left) and Save (Right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.onDelete != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDelete!();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: googleRed,
                        backgroundColor: const Color(0xFFFDE8E8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: googleRed),
                      label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    )
                  else
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: googleTextSecondary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: googleBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
