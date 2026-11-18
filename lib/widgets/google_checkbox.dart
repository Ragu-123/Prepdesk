import 'package:flutter/material.dart';

class GoogleCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GoogleCheckbox({
    Key? key,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(checked: value, enabled: true, child: InkResponse(
      onTap: () => onChanged(!value), radius: 24,
      child: SizedBox(width: 48, height: 48, child: Center(
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? Theme.of(context).colorScheme.primary : Colors.white,
            border: Border.all(
              color: value ? Theme.of(context).colorScheme.primary : const Color(0xFF747775),
              width: 1.75,
            ),
          ),
          child: value
              ? const Icon(
                  Icons.check,
                  size: 14,
                  color: Colors.white,
                )
              : null,
        ),
      )),
    ));
  }
}
