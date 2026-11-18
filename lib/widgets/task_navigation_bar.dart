import 'package:flutter/material.dart';
import '../utils/theme.dart';

class TaskNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int revisitCount;
  final int quizCount;

  const TaskNavigationBar({Key? key, required this.selectedIndex,
    required this.onSelected, this.revisitCount = 0, this.quizCount = 0, this.onCreate}) : super(key: key);

  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Center(heightFactor: 1, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Row(children: [
        Expanded(child: Container(
          height: 68,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: googleSurface,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: googleBorder.withOpacity(0.65)),
            boxShadow: [BoxShadow(color: googleTextPrimary.withOpacity(0.035), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            _destination(context, 0, Icons.today_outlined, 'Today', 0),
            _destination(context, 1, Icons.calendar_month_outlined, 'Timetable', 0),
            _destination(context, 2, Icons.history_rounded, 'Revisit', revisitCount),
            _destination(context, 3, Icons.fact_check_outlined, 'Quizzes', quizCount),
          ]),
        )),
        if (onCreate != null) ...[
          const SizedBox(width: 10),
          SizedBox(width: 56, height: 56, child: IconButton.filledTonal(
            onPressed: onCreate,
            tooltip: 'Create task, schedule, quiz or reminder',
            style: IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer, foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer),
            icon: const Icon(Icons.add_rounded, size: 28),
          )),
        ],
      ]),
    )),
  );

  Widget _destination(BuildContext context, int index, IconData icon, String label, int count) {
    final selected = selectedIndex == index;
    return Expanded(child: Semantics(
      selected: selected,
      button: true,
      label: count > 0 ? '$label, $count pending' : label,
      excludeSemantics: true,
      child: Tooltip(message: label, child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onSelected(index),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Badge(
              isLabelVisible: count > 0,
              label: Text(count > 99 ? '99+' : '$count'),
              child: Icon(icon, size: 24, color: selected ? Theme.of(context).colorScheme.onPrimaryContainer : googleTextSecondary),
            ),
          ),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? googleTextPrimary : googleTextSecondary)),
        ]),
      )),
    ));
  }
}
