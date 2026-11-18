import 'dart:async';

/// Shared invalidation signals; no note contents or credentials leave this bus.
class StudyDataEvents {
  static final instance = StudyDataEvents._();
  StudyDataEvents._();
  final _mistakes = StreamController<void>.broadcast();
  final _schedule = StreamController<void>.broadcast();
  final _privacy = StreamController<int>.broadcast();
  Stream<void> get mistakes => _mistakes.stream;
  Stream<void> get schedule => _schedule.stream;
  Stream<int> get privacy => _privacy.stream;
  int privacyRevision = 0;
  void mistakesChanged() => _mistakes.add(null);
  void scheduleChanged() => _schedule.add(null);
  void privacyChanged() => _privacy.add(++privacyRevision);
}
