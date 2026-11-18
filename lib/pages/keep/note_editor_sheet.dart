import 'dart:math';
import '../../widgets/protected_content.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/database_service.dart';
import '../../data/keep_note_model.dart';
import '../../services/notification_service.dart';
import '../../services/vault_service.dart';
import '../../utils/theme.dart';
import '../../widgets/top_banner_notification.dart';
import 'widgets/note_checklist_editor.dart';
import 'widgets/note_color_picker.dart';
import 'widgets/note_tags_editor.dart';

class NoteEditorSheet extends StatefulWidget {
  final KeepNote? note;
  final Function(KeepNote savedNote)? onSave;
  final VoidCallback? onDelete;

  const NoteEditorSheet({
    Key? key,
    this.note,
    this.onSave,
    this.onDelete,
  }) : super(key: key);

  @override
  _NoteEditorSheetState createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;

  late String _noteId;
  late String _selectedColor;
  late bool _isPinned;
  late bool _isArchived;
  late bool _isTodoList;
  late bool _isCode;
  late bool _isLocked;
  int? _reminderAt;
  String? _reminderRepeat;

  late List<ChecklistItem> _todoItems;
  late List<String> _tags;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _noteId = n?.id ?? 'note_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    _titleController = TextEditingController(text: n?.title ?? '');
    _contentController = TextEditingController(text: n?.content ?? '');

    _selectedColor = n?.color ?? '#FFFFFF';
    _isPinned = n?.isPinned ?? false;
    _isArchived = n?.isArchived ?? false;
    _isTodoList = n?.isTodoList ?? false;
    _isCode = n?.isCode ?? false;
    _isLocked = n?.isLocked ?? false;
    _reminderAt = n?.reminderAt;
    _reminderRepeat = n?.reminderRepeat;

    _todoItems = n?.todoItems != null ? List<ChecklistItem>.from(n!.todoItems) : [];
    _tags = n?.tags != null ? List<String>.from(n!.tags) : [];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Color get _backgroundColor {
    return KeepNoteColors.getColor(_selectedColor, isDark: false);
  }

  void _toggleTodoList() {
    setState(() {
      _isTodoList = !_isTodoList;
      if (_isTodoList && _todoItems.isEmpty && _contentController.text.trim().isNotEmpty) {
        final lines = _contentController.text.split('\n').where((l) => l.trim().isNotEmpty);
        _todoItems = lines
            .map((l) => ChecklistItem(
                  id: 'item_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
                  text: l.trim(),
                  checked: false,
                ))
            .toList();
      }
    });
  }

  Future<void> _toggleLock() async {
    if (!_isLocked) {
      final hasPin = await VaultService.instance.hasVaultPin();
      if (!hasPin) {
        if (!mounted) return;
        final setSuccess = await VaultService.instance.showSetPinDialog(
          context,
          title: 'Set Vault PIN First',
          subtitle: 'Create a PIN to protect this note.',
        );
        if (setSuccess != true) return;
      }
      setState(() => _isLocked = true);
      if (mounted) {
        TopBanner.show(
          context,
          title: 'Note Protected',
          message: 'Note will require PIN or biometrics to open.',
          icon: Icons.lock_rounded,
          color: Theme.of(context).colorScheme.primary,
        );
      }
    } else {
      setState(() => _isLocked = false);
      if (mounted) {
        TopBanner.show(
          context,
          title: 'Protection Removed',
          message: 'Note is now accessible without PIN.',
          icon: Icons.lock_open_rounded,
          color: googleAmber,
        );
      }
    }
  }

  Future<void> _openReminderPicker() async {
    final now = DateTime.now();

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Set Reminder',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: googleTextPrimary),
                ),
              ),
              const SizedBox(height: 12),

              // Preset 1: Later Today (6:00 PM)
              ListTile(
                leading: Icon(Icons.access_time_rounded, color: Theme.of(context).colorScheme.primary),
                title: const Text('Later today', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                trailing: const Text('6:00 PM', style: TextStyle(color: googleTextSecondary, fontSize: 13)),
                onTap: () {
                  final target = DateTime(now.year, now.month, now.day, 18, 0);
                  final effective = target.isAfter(now) ? target : now.add(const Duration(hours: 3));
                  setState(() {
                    _reminderAt = effective.millisecondsSinceEpoch;
                    _reminderRepeat = null;
                  });
                  Navigator.pop(ctx);
                },
              ),

              // Preset 2: Tomorrow Morning (8:00 AM)
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined, color: Color(0xFFFBBC04)),
                title: const Text('Tomorrow morning', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                trailing: const Text('8:00 AM', style: TextStyle(color: googleTextSecondary, fontSize: 13)),
                onTap: () {
                  final tomorrow = now.add(const Duration(days: 1));
                  final target = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8, 0);
                  setState(() {
                    _reminderAt = target.millisecondsSinceEpoch;
                    _reminderRepeat = null;
                  });
                  Navigator.pop(ctx);
                },
              ),

              // Preset 3: Tomorrow Evening (6:00 PM)
              ListTile(
                leading: const Icon(Icons.nights_stay_outlined, color: Colors.indigo),
                title: const Text('Tomorrow evening', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                trailing: const Text('6:00 PM', style: TextStyle(color: googleTextSecondary, fontSize: 13)),
                onTap: () {
                  final tomorrow = now.add(const Duration(days: 1));
                  final target = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 0);
                  setState(() {
                    _reminderAt = target.millisecondsSinceEpoch;
                    _reminderRepeat = null;
                  });
                  Navigator.pop(ctx);
                },
              ),

              // Option 4: Pick a date & time
              ListTile(
                leading: const Icon(Icons.edit_calendar_rounded, color: googleGreen),
                title: const Text('Pick a date & time', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: now,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (pickedDate == null || !mounted) return;

                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (pickedTime == null || !mounted) return;

                  final dt = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  );
                  setState(() {
                    _reminderAt = dt.millisecondsSinceEpoch;
                    _reminderRepeat = null;
                  });
                },
              ),

              if (_reminderAt != null)
                ListTile(
                  leading: const Icon(Icons.alarm_off_rounded, color: googleRed),
                  title: const Text('Remove Reminder', style: TextStyle(color: googleRed, fontWeight: FontWeight.bold, fontSize: 14)),
                  onTap: () {
                    setState(() {
                      _reminderAt = null;
                      _reminderRepeat = null;
                    });
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty && _todoItems.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final savedNote = KeepNote(
        id: _noteId,
        title: title,
        content: content,
        color: _selectedColor,
        isPinned: _isPinned,
        isArchived: _isArchived,
        isTodoList: _isTodoList,
        todoItems: _todoItems,
        tags: _tags,
        isCode: _isCode,
        isLocked: _isLocked,
        reminderAt: _reminderAt,
        reminderRepeat: _reminderRepeat,
        createdAt: widget.note?.createdAt ?? now,
        updatedAt: now,
      );

      await DatabaseService.instance.saveKeepNote(savedNote);

      // Schedule or cancel system notification for Keep Note Reminder.
      if (_isLocked) {
        await NotificationService.instance.refreshKeepNotePrivacy(_noteId);
      } else if (_reminderAt != null) {
        final scheduledDt = DateTime.fromMillisecondsSinceEpoch(_reminderAt!);
        await NotificationService.instance.scheduleKeepNoteReminder(
          noteId: _noteId,
          title: _isLocked ? 'Protected note reminder' : (title.isNotEmpty ? title : 'Note Reminder'),
          body: _isLocked ? 'Unlock Keep to view this note.' : (content.isNotEmpty ? content : (_todoItems.isNotEmpty ? '${_todoItems.length} checklist items' : 'Keep Note Reminder')),
          scheduledDate: scheduledDt,
          repeat: _reminderRepeat,
        );
      } else {
        await NotificationService.instance.cancelKeepNoteReminder(_noteId);
      }

      widget.onSave?.call(savedNote);

      if (mounted) {
        Navigator.pop(context);
        TopBanner.show(
          context,
          title: widget.note == null ? 'Note Created' : 'Note Saved',
          message: _isLocked ? 'Protected note saved in Keep.' : (title.isNotEmpty ? title : 'Note updated in Keep'),
          icon: Icons.check_circle_outline_rounded,
          color: googleGreen,
        );
      }
    } catch (e) {
      debugPrint('Error saving note: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        TopBanner.show(
          context,
          title: 'Error Saving Note',
          message: e.toString(),
          icon: Icons.error_outline_rounded,
          color: googleRed,
        );
      }
    }
  }

  Future<void> _handleDelete() async {
    if (widget.note == null) {
      Navigator.pop(context);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Note?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text('This note will be permanently deleted from Keep.', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: googleTextSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: googleRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.deleteKeepNote(_noteId);
      await NotificationService.instance.cancelKeepNoteReminder(_noteId);
      widget.onDelete?.call();
      if (mounted) {
        Navigator.pop(context);
        TopBanner.show(
          context,
          title: 'Note Deleted',
          message: 'Note removed from Keep.',
          icon: Icons.delete_outline_rounded,
          color: googleRed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ProtectedContent(
    protected: _isLocked,
    child: _buildSheet(context),
  );

  Widget _buildSheet(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Drag Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Actions Bar (Static Close at left, scrollable action icons in middle, static Save at right)
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: googleTextSecondary, size: 22),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Reminder Button
                          IconButton(
                            icon: Icon(
                              _reminderAt != null ? Icons.alarm_on_rounded : Icons.alarm_add_rounded,
                              color: _reminderAt != null ? Theme.of(context).colorScheme.primary : googleTextSecondary,
                              size: 22,
                            ),
                            tooltip: _reminderAt != null ? 'Edit Reminder' : 'Add Reminder',
                            onPressed: _openReminderPicker,
                          ),
                          // Protect / Lock Button
                          IconButton(
                            icon: Icon(
                              _isLocked ? Icons.lock_rounded : Icons.lock_outline_rounded,
                              color: _isLocked ? Theme.of(context).colorScheme.primary : googleTextSecondary,
                              size: 22,
                            ),
                            tooltip: _isLocked ? 'Protected Note' : 'Protect Note',
                            onPressed: _toggleLock,
                          ),
                          // Checklist Mode Button
                          IconButton(
                            icon: Icon(
                              _isTodoList ? Icons.check_box_rounded : Icons.check_box_outlined,
                              color: _isTodoList ? Theme.of(context).colorScheme.primary : googleTextSecondary,
                              size: 22,
                            ),
                            tooltip: 'Checklist Mode',
                            onPressed: _toggleTodoList,
                          ),
                          // Monospace / Code Button
                          IconButton(
                            icon: Icon(
                              _isCode ? Icons.code_rounded : Icons.data_object_rounded,
                              color: _isCode ? Theme.of(context).colorScheme.primary : googleTextSecondary,
                              size: 22,
                            ),
                            tooltip: 'Monospace Code Note',
                            onPressed: () => setState(() => _isCode = !_isCode),
                          ),
                          // Pin Button
                          IconButton(
                            icon: Icon(
                              _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                              color: _isPinned ? Theme.of(context).colorScheme.primary : googleTextSecondary,
                              size: 22,
                            ),
                            tooltip: _isPinned ? 'Unpin' : 'Pin to top',
                            onPressed: () => setState(() => _isPinned = !_isPinned),
                          ),
                          // Archive Button
                          IconButton(
                            icon: Icon(
                              _isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                              color: _isArchived ? Theme.of(context).colorScheme.primary : googleTextSecondary,
                              size: 22,
                            ),
                            tooltip: _isArchived ? 'Unarchive' : 'Archive',
                            onPressed: () => setState(() => _isArchived = !_isArchived),
                          ),
                          if (widget.note != null)
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: googleRed, size: 22),
                              tooltip: 'Delete Note',
                              onPressed: _handleDelete,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Badges row: Active reminder & Protected note
              if (_reminderAt != null || _isLocked) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (_reminderAt != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.alarm_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('EEE, d MMM • h:mm a').format(DateTime.fromMillisecondsSinceEpoch(_reminderAt!)),
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => setState(() {
                                _reminderAt = null;
                                _reminderRepeat = null;
                              }),
                              child: Icon(Icons.close_rounded, size: 14, color: Theme.of(context).colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    if (_isLocked)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_rounded, size: 13, color: Color(0xFFB45309)),
                            const SizedBox(width: 6),
                            const Text(
                              'Protected Note',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => setState(() => _isLocked = false),
                              child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFB45309)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // 3. Title Field
              TextField(
                controller: _titleController,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: googleTextPrimary,
                  letterSpacing: -0.4,
                ),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9AA0A6),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
              ),

              const SizedBox(height: 8),

              // 4. Content or Modular Checklist
              if (!_isTodoList) ...[
                TextField(
                  controller: _contentController,
                  maxLines: 8,
                  minLines: 4,
                  style: TextStyle(
                    fontSize: 15,
                    color: googleTextPrimary,
                    fontFamily: _isCode ? 'monospace' : null,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Take a note...',
                    hintStyle: TextStyle(fontSize: 15, color: Color(0xFF9AA0A6)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ] else ...[
                NoteChecklistEditor(
                  items: _todoItems,
                  onChanged: (newItems) => setState(() => _todoItems = newItems),
                ),
              ],

              const SizedBox(height: 12),

              // 5. Modular Tags Editor
              NoteTagsEditor(
                tags: _tags,
                onChanged: (newTags) => setState(() => _tags = newTags),
              ),

              const Divider(height: 24, thickness: 0.8),

              // 6. Modular Color Picker
              NoteColorPicker(
                selectedColor: _selectedColor,
                onColorSelected: (hex) => setState(() => _selectedColor = hex),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
