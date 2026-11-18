import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/data/quiz_trap_matcher.dart';
import 'package:tasks/services/appearance_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:tasks/pages/tabs/widgets/today_progress_summary.dart';

void main() {
  test('Matching tolerates punctuation and does not confuse unrelated subjects', () {
    final trap = {'subject': '  Linear-Algebra ', 'quiz_title': 'Old quiz'};
    expect(QuizTrapMatcher.matches(trap, quizTitle: 'Week 3', subject: 'LINEAR ALGEBRA'), isTrue);
    expect(QuizTrapMatcher.matches(trap, quizTitle: 'New test', subject: 'Mathematics', syllabus: 'Calculus / Linear Algebra'), isTrue);
    expect(QuizTrapMatcher.matches(trap, quizTitle: 'New quiz', subject: 'Algebraic topology'), isFalse);
    expect(QuizTrapMatcher.matches({'quiz_title': 'Legacy Quiz'}, quizTitle: 'legacy quiz'), isTrue);
    expect(QuizTrapMatcher.matches({'quiz_title': 'Legacy Quiz'}, quizTitle: 'unrelated quiz'), isFalse);
  });
  test('Adaptive accents are stable and disabling restores the fixed app accent', () {
    final appearance = AppearanceService.instance;
    expect(AppearanceService.seedColor(' Linear Algebra '), AppearanceService.seedColor('linear algebra'));
    appearance.enabled = false;
    expect(appearance.colorFor('Linear Algebra'), googleBlue);
    expect(appearance.theme, lightTheme);
    appearance.enabled = true;
    expect(AppearanceService.palette, contains(appearance.colorFor('Linear Algebra')));
    expect(appearance.theme.brightness, lightTheme.brightness);
  });
  testWidgets('Study summary fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: lightTheme, home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: Scaffold(body: SingleChildScrollView(child: TodayProgressSummary(
        watchedHours: 12.5, targetHours: 18, lecturesDone: 8, lecturesTotal: 12,
        revisitsDone: 2, revisitsTotal: 5, quizzesDone: 1, quizzesTotal: 3,
        onSection: (_) {}, onAddSession: () {}, onTimetable: () {}))),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Watched'), findsOneWidget);
  });
}
