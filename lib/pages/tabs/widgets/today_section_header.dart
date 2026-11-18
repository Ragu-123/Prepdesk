import 'package:flutter/material.dart';
import '../../../utils/theme.dart';

class TodaySectionHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double extent;
  TodaySectionHeader({required this.child, this.extent = 78});
  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox(height: extent, child: Material(
    color: googleBackground, elevation: overlapsContent ? 1 : 0,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: DecoratedBox(decoration: BoxDecoration(color: googleHairline,
        borderRadius: BorderRadius.circular(28)), child: Padding(padding: const EdgeInsets.all(4), child: child))),
  ));
  @override
  bool shouldRebuild(covariant TodaySectionHeader oldDelegate) => true;
}
