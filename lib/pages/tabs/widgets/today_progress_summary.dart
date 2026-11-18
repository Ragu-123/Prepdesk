import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../utils/theme.dart';

class TodayProgressSummary extends StatelessWidget {
  final double watchedHours;
  final double targetHours;
  final int lecturesDone;
  final int lecturesTotal;
  final int revisitsDone;
  final int revisitsTotal;
  final int quizzesDone;
  final int quizzesTotal;
  final ValueChanged<int> onSection;
  final VoidCallback? onAddSession;
  final VoidCallback? onTimetable;

  const TodayProgressSummary({Key? key, required this.watchedHours, required this.targetHours,
    required this.lecturesDone, required this.lecturesTotal, required this.revisitsDone,
    required this.revisitsTotal, required this.quizzesDone, required this.quizzesTotal,
    required this.onSection, this.onAddSession, this.onTimetable}) : super(key: key);

  Color _accent(BuildContext context) => Theme.of(context).colorScheme.primary;
  @override
  Widget build(BuildContext context) {
    final progress = targetHours > 0 ? (watchedHours / targetHours).clamp(0.0, 1.0).toDouble() : 0.0;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(children: [
        LayoutBuilder(builder: (context, constraints) {
          final ringSize = math.min(240.0, constraints.maxWidth * 0.47);
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
          final ring = Semantics(label: '${watchedHours.toStringAsFixed(1)} of ${targetHours.toStringAsFixed(1)} study hours completed',
            child: SizedBox(width: ringSize, height: ringSize,
              child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: progress),
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 500),
                builder: (_, value, child) => CustomPaint(painter: _ProgressRing(value, _accent(context)), child: child),
                child: Padding(padding: EdgeInsets.all(ringSize * 0.17),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('Watched', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    FittedBox(child: Text('${watchedHours.toStringAsFixed(1)}h',
                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700, letterSpacing: -1.2))),
                    const SizedBox(height: 8),
                    FittedBox(child: Text('of ${targetHours.toStringAsFixed(1)}h',
                      style: TextStyle(color: _accent(context), fontSize: 14, fontWeight: FontWeight.w700))),
                  ])),
              )),
          );
          final metrics = Column(children: [
            _metric(context, 'Lectures', '$lecturesDone of $lecturesTotal', Icons.play_lesson_outlined,
              lecturesTotal > 0 ? lecturesDone / lecturesTotal : 0, () => onSection(0)),
            const SizedBox(height: 8),
            _metric(context, 'Revisits', '$revisitsDone of $revisitsTotal', Icons.history_rounded,
              revisitsTotal > 0 ? revisitsDone / revisitsTotal : 0, () => onSection(1)),
            const SizedBox(height: 8),
            _metric(context, 'Quizzes', '$quizzesDone of $quizzesTotal', Icons.quiz_outlined,
              quizzesTotal > 0 ? quizzesDone / quizzesTotal : 0, () => onSection(2)),
          ]);
          if (largeText) return Column(children: [ring, const SizedBox(height: 20), metrics]);
          return Row(children: [ring, const SizedBox(width: 14), Expanded(child: metrics)]);
        }),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: FilledButton.tonalIcon(onPressed: onAddSession,
            icon: const Icon(Icons.add_rounded), label: const Text('Add session'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: onTimetable,
            icon: const Icon(Icons.calendar_month_outlined), label: const Text('Timetable'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)))),
        ]),
      ]));
  }

  Widget _metric(BuildContext context, String title, String value, IconData icon, double progress, VoidCallback onTap) =>
    Material(color: _accent(context).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Stack(children: [
        Positioned.fill(child: FractionallySizedBox(alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0).toDouble(), child: ColoredBox(color: _accent(context).withValues(alpha: 0.13)))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(width: 36, height: 42, decoration: BoxDecoration(
              color: _accent(context).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
              child: Icon(icon, size: 21, color: _accent(context))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accent(context))),
              FittedBox(alignment: Alignment.centerLeft, fit: BoxFit.scaleDown, child: Text(value,
                style: TextStyle(fontSize: 21, height: 1.3, fontWeight: FontWeight.w700, color: _accent(context)))),
            ])),
          ])),
      ])));

}

class _ProgressRing extends CustomPainter {
  final double value;
  final Color color;
  _ProgressRing(this.value, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * 0.105;
    final rect = Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = width..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = const Color(0xFFE4E9ED));
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false,
      paint..color = color);
  }
  @override
  bool shouldRepaint(covariant _ProgressRing oldDelegate) => oldDelegate.value != value || oldDelegate.color != color;
}
