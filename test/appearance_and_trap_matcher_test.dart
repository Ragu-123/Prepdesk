import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/data/quiz_trap_matcher.dart';
import 'package:tasks/services/appearance_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:tasks/pages/tabs/widgets/today_progress_summary.dart';
import 'dart:math';

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
    appearance.enabled = false;
    expect(appearance.colorFor('Linear Algebra'), googleBlue);
    expect(appearance.theme, lightTheme);
    appearance.enabled = true;
    expect(AppearanceService.palette, contains(appearance.colorFor('Linear Algebra')));
    expect(appearance.colorFor('Linear Algebra'), appearance.colorFor('Thermodynamics'));
    expect(appearance.theme.colorScheme.primary, appearance.accent);
    expect(appearance.theme.brightness, lightTheme.brightness);
  });
  test('Each launch excludes the previous accent while retaining the full palette', () {
    final random = Random(42);
    final visited = <int>{};
    var previous = 2;
    for (var i = 0; i < 100; i++) {
      final next = AppearanceService.nextAccentIndex(previous, random);
      expect(next, isNot(previous));
      expect(next, inInclusiveRange(0, AppearanceService.palette.length - 1));
      visited.add(next);
      previous = next;
    }
    expect(visited.length, AppearanceService.palette.length);
  });
  test('All accent palettes retain readable text and themed form controls', () {
    double contrast(Color a, Color b) {
      final light = max(a.computeLuminance(), b.computeLuminance());
      final dark = min(a.computeLuminance(), b.computeLuminance());
      return (light + 0.05) / (dark + 0.05);
    }
    for (final accent in AppearanceService.palette) {
      final theme = buildLightTheme(accent);
      expect(contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary), greaterThanOrEqualTo(4.5));
      expect(contrast(theme.colorScheme.primaryContainer, theme.colorScheme.onPrimaryContainer), greaterThanOrEqualTo(4.5));
      expect((theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder).borderSide.color, accent);
      expect(theme.progressIndicatorTheme.color, accent);
      expect(theme.textSelectionTheme.cursorColor, accent);
      expect(theme.floatingActionButtonTheme.backgroundColor, theme.colorScheme.primaryContainer);
    }
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
