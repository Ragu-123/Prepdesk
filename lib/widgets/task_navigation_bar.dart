import 'package:flutter/material.dart';
import '../utils/theme.dart';

class TaskNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int revisitCount;
  final int quizCount;

  const TaskNavigationBar({Key? key, required this.selectedIndex,
    required this.onSelected, this.revisitCount = 0, this.quizCount = 0}) : super(key: key);

  @override
  Widget build(BuildContext context) => BottomAppBar(
    color: googleSurface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    notchMargin: 8,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    height: 80,
    shape: const CircularNotchedRectangle(),
    child: Row(children: [
      _destination(context, 0, Icons.today_outlined, 'Today', 0),
      _destination(context, 1, Icons.calendar_month_outlined, 'Timetable', 0),
      const SizedBox(width: 56),
      _destination(context, 2, Icons.history_rounded, 'Revisit', revisitCount),
      _destination(context, 3, Icons.fact_check_outlined, 'Quizzes', quizCount),
    ]),
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
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? googleBlueContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Badge(
              isLabelVisible: count > 0,
              label: Text(count > 99 ? '99+' : '$count'),
              child: Icon(icon, size: 23, color: selected ? googleOnBlueContainer : googleTextSecondary),
            ),
          ),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? googleTextPrimary : googleTextSecondary)),
        ]),
      )),
    ));
  }
}
