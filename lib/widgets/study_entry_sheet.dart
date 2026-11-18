import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/database_service.dart';
import '../utils/url_helper.dart';

Future<void> showStudyEntry(BuildContext context, Map<String, dynamic> entry, {
  required bool lecture,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _StudyEntrySheet(entry: entry, lecture: lecture),
);

class _StudyEntryMenu extends StatelessWidget {
  const _StudyEntryMenu({required this.onEdit, required this.onDelete, required this.kind});
  final VoidCallback onEdit, onDelete;
  final String kind;

  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
    tooltip: '$kind options',
    icon: const Icon(Icons.more_vert_rounded),
    onSelected: (edit) => edit ? onEdit() : onDelete(),
    itemBuilder: (context) => [
      PopupMenuItem(value: true, child: ListTile(leading: const Icon(Icons.edit_outlined),
        title: Text('Edit $kind'), contentPadding: EdgeInsets.zero)),
      PopupMenuItem(value: false, child: ListTile(leading: Icon(Icons.delete_outline_rounded,
        color: Theme.of(context).colorScheme.error), title: Text('Delete $kind'), contentPadding: EdgeInsets.zero)),
    ],
  );
}

Future<bool> confirmStudyEntryDeletion(BuildContext context, Map<String, dynamic> entry, {required bool lecture}) async {
  final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
    title: Text(lecture ? 'Delete lecture?' : 'Delete quiz?'),
    content: Text(lecture
      ? 'This removes the lecture and its unfinished revisits. Completed revisits stay in your history.'
      : 'This removes the quiz from your schedule. Your logged mistakes stay in the notebook.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true),
        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError), child: const Text('Delete')),
    ],
  ));
  if (confirmed != true || !context.mounted) return false;
  try {
    final id = entry['id'] as int;
    final db = DatabaseService.instance;
    if (lecture) {
      await db.deleteLecture(id);
    } else {
      await db.deleteQuiz(id);
    }
    return true;
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not delete this entry. Try again.')));
    return false;
  }
}

class _StudyEntrySheet extends StatefulWidget {
  const _StudyEntrySheet({required this.entry, required this.lecture});
  final Map<String, dynamic> entry;
  final bool lecture;
  @override
  State<_StudyEntrySheet> createState() => _StudyEntrySheetState();
}

class _StudyEntrySheetState extends State<_StudyEntrySheet> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  bool _editing = false;
  bool _busy = false;
  String? _error;
  late final DateTime? _originalDate = DatabaseService.parseStudyDate(_read('date_str'));
  DateTime? _pickedDate;
  DateTime? get _date => _pickedDate ?? _originalDate;
  late String _quizType = _read('quiz_type', 'WEEKLY_QUIZ');
  String get _kind => widget.lecture ? 'lecture' : 'quiz';

  String _read(String key, [String fallback = '']) => widget.entry[key]?.toString() ?? fallback;
  String _value(String key) => _fields[key]!.text.trim();
  String _formatDate(DateTime date) => DateFormat('EEE, d MMM yyyy').format(date);

  @override
  void initState() {
    super.initState();
    final topic = _read('topic');
    final separator = topic.indexOf('•');
    final details = _read('details').trim();
    final title = widget.lecture
      ? (details.isNotEmpty ? details : (separator < 0 ? topic : topic.substring(separator + 1).trim()))
      : _read('title');
    final subject = widget.lecture ? (separator < 0 ? '' : topic.substring(0, separator).trim()) : _read('subject');
    final values = {
      'title': title, 'subject': subject,
      if (widget.lecture) ...{'session': _read('session_block'), 'hours': _read('duration_hours', '1.5')}
      else ...{'minutes': _read('duration_mins', '45'), 'marks': _read('total_marks', '25'),
        'module': _read('module_name'), 'syllabus': _read('syllabus_topics'), 'link': _read('action_url')},
    };
    for (final entry in values.entries) {
      _fields[entry.key] = TextEditingController(text: entry.value);
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) { field.dispose(); }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final current = _date ?? DateTime.now();
    final date = await showDatePicker(context: context, initialDate: current,
      firstDate: DateTime(current.year < 2000 ? current.year : 2000),
      lastDate: DateTime(current.year > 2100 ? current.year : 2100, 12, 31));
    if (date != null && mounted) setState(() { _pickedDate = date; _error = null; });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final date = _date;
    if (date == null) {
      setState(() => _error = 'Choose a scheduled date.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final db = DatabaseService.instance;
      final id = widget.entry['id'] as int;
      if (widget.lecture) {
        await db.editLecture(id, title: _value('title'), subject: _value('subject'), date: date,
          hours: double.parse(_value('hours')), session: _value('session'));
      } else {
        await db.editQuiz(id, title: _value('title'), subject: _value('subject'), type: _quizType,
          date: date, minutes: int.parse(_value('minutes')), marks: int.parse(_value('marks')),
          module: _value('module'), syllabus: _value('syllabus'), link: _value('link'));
      }
      if (mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() { _busy = false; _error = 'Could not save changes. Try again.'; });
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    final deleted = await confirmStudyEntryDeletion(context, widget.entry, lecture: widget.lecture);
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context);
    } else {
      setState(() => _busy = false);
    }
  }

  Widget _field(String key, String label, {bool required = false, bool numeric = false}) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
      controller: _fields[key], enabled: !_busy,
      decoration: InputDecoration(labelText: label),
      keyboardType: numeric ? TextInputType.numberWithOptions(decimal: key == 'hours') : TextInputType.text,
      maxLines: key == 'syllabus' ? 3 : 1,
      validator: (input) {
        final value = input?.trim() ?? '';
        if (required && value.isEmpty) return 'Enter $label';
        if (numeric) {
          final number = key == 'hours' ? double.tryParse(value) : int.tryParse(value);
          if (number == null || !number.isFinite || (key == 'marks' ? number < 0 : number <= 0)) {
            return 'Enter a valid number';
          }
        }
        return null;
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final types = {'WEEKLY_QUIZ': 'Weekly quiz', 'TEST_SERIES': 'Test series'};
    return SafeArea(top: false, child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(_editing ? 'Edit $_kind' : (_value('title').isEmpty ? 'Untitled $_kind' : _value('title')),
              style: theme.textTheme.headlineSmall)),
            if (!_editing && !_busy) _StudyEntryMenu(kind: _kind, onEdit: () => setState(() => _editing = true), onDelete: _delete),
          ]),
          const SizedBox(height: 16),
          if (_editing) ...[
            _field('title', 'Title', required: true),
            _field('subject', 'Subject'),
            OutlinedButton.icon(onPressed: _busy ? null : _pickDate, icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_date == null ? 'Choose date' : _formatDate(_date!))),
            const SizedBox(height: 12),
            if (widget.lecture) ...[_field('session', 'Session block'), _field('hours', 'Hours', numeric: true)]
            else ...[
              DropdownButtonFormField<String>(initialValue: _quizType, decoration: const InputDecoration(labelText: 'Quiz type'),
                items: {...types, if (!types.containsKey(_quizType)) _quizType: _quizType}.entries
                  .map((type) => DropdownMenuItem(value: type.key, child: Text(type.value))).toList(),
                onChanged: _busy ? null : (type) => setState(() => _quizType = type!)),
              const SizedBox(height: 12),
              _field('minutes', 'Minutes', numeric: true), _field('marks', 'Marks', numeric: true),
              _field('module', 'Module'), _field('syllabus', 'Syllabus'), _field('link', 'Test link'),
            ],
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            Align(alignment: Alignment.centerRight, child: FilledButton(
              onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save changes'))),
          ] else ...[
            if (_value('subject').isNotEmpty) Text(_value('subject'), style: theme.textTheme.titleMedium),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (_date != null) Chip(label: Text(_formatDate(_date!))),
              Chip(label: Text(widget.lecture ? '${_value('hours')} h' : '${_value('minutes')} min')),
              if (widget.lecture && _value('session').isNotEmpty) Chip(label: Text(_value('session'))),
              if (!widget.lecture) Chip(label: Text(types[_quizType] ?? 'Quiz')),
              if (!widget.lecture) Chip(label: Text('${_value('marks')} marks')),
              if (_read('status').toUpperCase() == 'COMPLETED') const Chip(label: Text('Completed')),
            ]),
            if (!widget.lecture && _value('module').isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(_value('module'), style: theme.textTheme.titleMedium)),
            if (!widget.lecture && _value('syllabus').isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(_value('syllabus'))),
            if (!widget.lecture && _value('link').isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 16), child: FilledButton.icon(
                onPressed: () => openExternalUrl(_value('link')), icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Start test'))),
          ],
        ])),
    ));
  }
}
