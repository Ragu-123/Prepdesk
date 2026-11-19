import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../data/database_service.dart';
import '../data/quiz_trap_matcher.dart';
import '../utils/url_helper.dart';
import 'add_mistake_modal_sheet.dart';

class StudyReviewActions extends StatelessWidget {
  const StudyReviewActions({super.key, required this.onReview, this.count, this.onStart, this.startLabel = 'Start quiz'});

  final VoidCallback onReview;
  final int? count;
  final VoidCallback? onStart;
  final String startLabel;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton.icon(
        onPressed: onReview,
        icon: const Icon(Icons.fact_check_outlined, size: 18),
        label: Text(count == null || count == 0 ? 'Review mistakes' : 'Review mistakes ($count)'),
      ),
      if (onStart != null) FilledButton.tonalIcon(
        onPressed: onStart,
        icon: const Icon(Icons.open_in_new_rounded, size: 16),
        label: Text(startLabel),
      ),
    ],
  );
}

Future<void> showQuizTrapsModalSheet(
  BuildContext context, {
  required String quizTitle,
  String? subject,
  String? module,
  String? syllabus,
  VoidCallback? onDataChanged,
}) => _openReview(context, title: quizTitle, quizTitle: quizTitle, subject: subject,
  topics: [quizTitle, if (module != null) module, ...?syllabus?.split(RegExp(r'[,;/\n•]'))],
  onDataChanged: onDataChanged);

Future<void> showRevisitMistakeReview(
  BuildContext context, String revisit, {
  String? subject,
  VoidCallback? onDataChanged,
}) {
  final parts = revisit.split('•').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  final topic = parts.length > 1 ? parts.skip(1).join(' • ') : revisit.trim();
  return _openReview(context, title: topic.isEmpty ? 'Revisit' : topic,
    subject: parts.length > 1 ? parts.first : subject, topics: [topic],
    initialTopic: topic, onDataChanged: onDataChanged);
}

Future<void> _openReview(BuildContext context, {
  required String title, required List<String> topics, String? quizTitle,
  String? subject, String? initialTopic, VoidCallback? onDataChanged,
}) => showModalBottomSheet<void>(
  context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
  builder: (context) => _MistakeReviewSheet(
    title: title, topics: topics, quizTitle: quizTitle, subject: subject,
    initialTopic: initialTopic, onDataChanged: onDataChanged,
  ),
);

class _MistakeReviewSheet extends StatefulWidget {
  const _MistakeReviewSheet({required this.title, required this.topics, this.subject,
    this.quizTitle, this.initialTopic, this.onDataChanged});

  final String title;
  final List<String> topics;
  final String? subject;
  final String? quizTitle;
  final String? initialTopic;
  final VoidCallback? onDataChanged;

  @override
  State<_MistakeReviewSheet> createState() => _MistakeReviewSheetState();
}

class _MistakeReviewSheetState extends State<_MistakeReviewSheet> {
  final _db = DatabaseService.instance;
  late var _results = _load();
  final _updating = <int>{};

  Future<({List<Map<String, dynamic>> topic, List<Map<String, dynamic>> subject, List<String> subjects})>
  _load() async {
    final rows = await _db.getMistakeRecordsFiltered();
    final subjects = await _db.getOnlySubjectsForDropdown();
    final normalized = QuizTrapMatcher.normalize(widget.subject ?? '');
    final hasSubject = normalized.isNotEmpty && normalized != 'all subjects';
    final subjectRows = rows.where((row) => QuizTrapMatcher.matches(row,
      quizTitle: widget.quizTitle ?? '', subject: widget.subject, syllabus: widget.topics.join(' '))).toList();
    final topicRows = (hasSubject || widget.quizTitle != null ? subjectRows : rows)
        .where((row) => QuizTrapMatcher.matchesTopic(row, quizTitle: widget.quizTitle, topics: widget.topics)).toList();
    if (!hasSubject && widget.quizTitle == null) {
      final matchedSubjects = topicRows.map((row) => QuizTrapMatcher.normalize(row['subject']?.toString() ?? ''))
          .where((subject) => subject.isNotEmpty).toSet();
      subjectRows.addAll(rows.where((row) => matchedSubjects.contains(
        QuizTrapMatcher.normalize(row['subject']?.toString() ?? '')) && !subjectRows.contains(row)));
    }
    return (topic: topicRows, subject: subjectRows, subjects: subjects);
  }

  Future<void> _setResolved(int id, bool resolved) async {
    if (!_updating.add(id)) return;
    setState(() {});
    try {
      await _db.toggleMistakeResolved(id, resolved);
      widget.onDataChanged?.call();
      if (mounted) setState(() => _results = _load());
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the mistake.')),
      );
    } finally {
      if (mounted) setState(() => _updating.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(heightFactor: 0.84, child: DefaultTabController(
      length: 2,
      child: FutureBuilder(
        future: _results,
        builder: (context, snapshot) {
          final results = snapshot.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 16, 12), child: Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Review mistakes', style: theme.textTheme.titleLarge),
                  Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ])),
                IconButton.filledTonal(tooltip: 'Log a mistake', icon: const Icon(Icons.add_rounded),
                  onPressed: results == null ? null : () => showAddMistakeModalSheet(context,
                    initialTopic: widget.initialTopic, initialQuizTitle: widget.quizTitle,
                    initialSubject: widget.subject, availableSubjects: results.subjects,
                    onSaved: () {
                      widget.onDataChanged?.call();
                      if (mounted) setState(() => _results = _load());
                    },
                  )),
              ],
            )),
            const TabBar(tabs: [Tab(text: 'This topic'), Tab(text: 'All subject mistakes')]),
            Expanded(child: results == null
              ? Center(child: snapshot.hasError ? const Text('Could not load mistakes.') : const CircularProgressIndicator())
              : TabBarView(children: [
                _list(results.topic, 'No mistakes logged for this topic.'),
                _list(results.subject, 'No mistakes logged for this subject.'),
              ])),
          ]);
        },
      ),
    ));
  }

  Widget _list(List<Map<String, dynamic>> rows, String empty) {
    if (rows.isEmpty) return Center(child: Padding(
      padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center),
    ));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final id = row['id'] as int;
        final resolved = ['RESOLVED', 'COMPLETED', 'DONE'].contains(row['status']?.toString().toUpperCase());
        return Card(key: ValueKey(id), child: ExpansionTile(
          leading: Icon(resolved ? Icons.check_circle_outline_rounded : Icons.fact_check_outlined),
          title: Text(row['topic']?.toString() ?? 'Mistake'),
          subtitle: Text([row['subject']?.toString() ?? '', if (resolved) 'Resolved']
              .where((part) => part.isNotEmpty).join(' · ')),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('Question', row['question_text']),
            _field('Your answer', row['wrong_answer']),
            _field('Correct answer', row['correct_answer']),
            _field('What went wrong', row['mistake_reason']),
            _field('Takeaway', row['key_takeaway']),
            TextButton.icon(
              onPressed: _updating.contains(id) ? null : () => _setResolved(id, !resolved),
              icon: Icon(resolved ? Icons.undo_rounded : Icons.check_rounded),
              label: Text(resolved ? 'Reopen mistake' : 'Mark resolved'),
            ),
          ],
        ));
      },
    );
  }

  Widget _field(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        MarkdownBody(data: text, selectable: true, onTapLink: (_, href, _) => openExternalUrl(href)),
      ],
    ));
  }
}
