/// Quiz identity is not the subject boundary: subject traps carry forward.
class QuizTrapMatcher {
  static String normalize(String value) => value.toLowerCase()
      .replaceAll('&', ' and ').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool _contains(String value, String phrase) => phrase.isNotEmpty &&
      ' $value '.contains(' $phrase ');

  static bool matches(Map<String, dynamic> record, {required String quizTitle,
    String? subject, String? module, String? syllabus}) {
    final source = normalize(record['subject']?.toString() ?? '');
    final target = normalize(subject ?? '');
    final context = normalize('${subject ?? ''} ${module ?? ''} ${syllabus ?? ''} $quizTitle');
    if (source.isNotEmpty && target.isNotEmpty && target != 'all subjects') {
      return _contains(context, source) || _contains(source, target);
    }
    if (source.isNotEmpty && _contains(context, source)) return true;
    final original = normalize(record['quiz_title']?.toString() ?? '');
    return original.isNotEmpty && original == normalize(quizTitle);
  }
}
