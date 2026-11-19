import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../data/database_service.dart';
import '../../data/keep_note_model.dart';
import '../../services/study_data_events.dart';
import '../../services/vault_service.dart';
import '../../utils/theme.dart';
import '../../widgets/protected_content.dart';
import 'note_editor_sheet.dart';

class NoteReaderPage extends StatefulWidget {
  final KeepNote note;
  final VoidCallback? onChanged;
  const NoteReaderPage._({Key? key, required this.note, this.onChanged}) : super(key: key);

  static Future<void> open(BuildContext context, String noteId, {VoidCallback? onChanged}) async {
    final note = await DatabaseService.instance.getKeepNoteById(noteId);
    if (note == null || !context.mounted) return;
    if (note.isLocked && !await VaultService.instance.authenticate(context)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NoteReaderPage._(note: note, onChanged: onChanged)));
    onChanged?.call();
  }

  @override
  State<NoteReaderPage> createState() => _NoteReaderPageState();
}

class _NoteReaderPageState extends State<NoteReaderPage> {
  late KeepNote _note;
  StreamSubscription<int>? _privacy;
  bool _editing = false;
  bool _checking = true;
  bool _requiresUnlock = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _privacy = StudyDataEvents.instance.privacy.listen((_) => _reload());
    _reload();
  }
  @override
  void dispose() { _privacy?.cancel(); super.dispose(); }

  Future<void> _reload() async {
    final latest = await DatabaseService.instance.getKeepNoteById(_note.id);
    if (!mounted) return;
    if (latest == null) { Navigator.pop(context); return; }
    setState(() {
      if (!_editing && latest.isLocked && !_note.isLocked) _requiresUnlock = true;
      _note = latest;
      _checking = false;
    });
  }

  Future<void> _edit() async {
    if (_editing) return;
    _editing = true;
    try {
      final latest = await DatabaseService.instance.getKeepNoteById(_note.id);
      if (!mounted || latest == null) return;
      if (latest.isLocked && !_note.isLocked && !await VaultService.instance.authenticate(context)) return;
      if (!mounted) return;
      setState(() => _note = latest);
      await showModalBottomSheet<void>(context: context, isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => NoteEditorSheet(note: _note,
          onSave: (_) => widget.onChanged?.call(), onDelete: widget.onChanged));
      await _reload();
    } finally { _editing = false; }
  }

  Future<void> _copyNote() async {
    final latest = await DatabaseService.instance.getKeepNoteById(_note.id);
    if (!mounted || latest == null || _requiresUnlock || _checking) return;
    if (latest.isLocked && !await VaultService.instance.authenticate(context)) return;
    if (!mounted) return;
    final text = [
      if (latest.title.isNotEmpty) latest.title,
      if (latest.content.isNotEmpty) latest.content,
      if (latest.isTodoList && latest.todoItems.isNotEmpty)
        latest.todoItems.map((item) => '- [${item.checked ? 'x' : ' '}] ${item.text}').join('\n'),
      if (latest.tags.isNotEmpty) latest.tags.map((tag) => '#$tag').join(' '),
    ].join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note copied to clipboard.')));
  }

  @override
  Widget build(BuildContext context) {
    final background = KeepNoteColors.getColor(_note.color);
    return ProtectedContent(protected: _note.isLocked, child: Scaffold(
      backgroundColor: background,
      appBar: AppBar(backgroundColor: background, title: const Text('Keep'),
        leading: IconButton(tooltip: 'Back to notes', onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded)),
        actions: [
          if (!_checking && !_requiresUnlock) IconButton(tooltip: 'Copy note',
            icon: const Icon(Icons.copy_all_outlined), onPressed: _copyNote),
          if (_note.isLocked) const Padding(padding: EdgeInsets.only(right: 20),
          child: Icon(Icons.lock_outline_rounded, color: googleTextSecondary))]),
      body: _checking ? const Center(child: CircularProgressIndicator()) : _requiresUnlock ? Center(child: FilledButton.icon(
        icon: const Icon(Icons.lock_outline_rounded), label: const Text('Unlock note'),
        onPressed: () async {
          if (await VaultService.instance.authenticate(context) && mounted) setState(() => _requiresUnlock = false);
        },
      )) : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(_note.title.isNotEmpty ? _note.title : 'Untitled note',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 14),
          Text('Updated ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(_note.updatedAt))}',
            style: const TextStyle(fontSize: 12, color: googleTextSecondary)),
          const SizedBox(height: 28),
          if (_note.content.isNotEmpty) SelectableText(_note.content,
            style: TextStyle(fontSize: _note.isCode ? 15 : 17, height: 1.65,
              fontFamily: _note.isCode ? 'monospace' : null)),
          if (_note.isTodoList) ..._note.todoItems.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(item.checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: item.checked ? Theme.of(context).colorScheme.primary : googleTextSecondary),
              const SizedBox(width: 12), Expanded(child: SelectableText(item.text,
                style: TextStyle(fontSize: 17, height: 1.5,
                  decoration: item.checked ? TextDecoration.lineThrough : null))),
            ]))),
          if (_note.tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 28),
            child: Wrap(spacing: 8, runSpacing: 8, children: _note.tags.map((tag) => Chip(label: Text(tag))).toList())),
          if (_note.reminderAt != null) Padding(padding: const EdgeInsets.only(top: 16),
            child: Chip(avatar: const Icon(Icons.alarm_rounded, size: 18),
              label: Text(DateFormat('d MMM, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(_note.reminderAt!))))),
        ])),
      floatingActionButton: _requiresUnlock || _checking ? null : FloatingActionButton.extended(
        onPressed: _edit, icon: const Icon(Icons.edit_outlined), label: const Text('Edit note')),
    ));
  }
}
