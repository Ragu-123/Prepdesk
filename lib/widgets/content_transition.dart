import 'package:flutter/material.dart';

/// A short entrance on tab changes; the child tree and scroll positions survive.
class ContentTransition extends StatefulWidget {
  final int selection;
  final Widget child;
  const ContentTransition({Key? key, required this.selection, required this.child}) : super(key: key);
  @override
  State<ContentTransition> createState() => _ContentTransitionState();
}

class _ContentTransitionState extends State<ContentTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this,
    duration: const Duration(milliseconds: 220), value: 1);
  late final Animation<double> _fade = Tween<double>(begin: 0.35, end: 1)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(covariant ContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child));
}
