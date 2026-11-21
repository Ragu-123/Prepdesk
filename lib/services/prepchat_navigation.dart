import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> openPrepChat(BuildContext context, String destination) async {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  try {
    await const MethodChannel('io.github.thelazyindian.tasks/native')
        .invokeMethod<void>(destination, {
      'primary': colors.primary.toARGB32(),
      'primaryContainer': colors.primaryContainer.toARGB32(),
      'onPrimaryContainer': colors.onPrimaryContainer.toARGB32(),
      'background': theme.scaffoldBackgroundColor.toARGB32(),
      'surface': colors.surface.toARGB32(),
      'onSurface': colors.onSurface.toARGB32(),
      'onSurfaceVariant': colors.onSurfaceVariant.toARGB32(),
      'surfaceContainer': colors.surfaceContainer.toARGB32(),
      'outlineVariant': colors.outlineVariant.toARGB32(),
    });
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open PrepChat.')),
      );
    }
  } on MissingPluginException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PrepChat is available in the Prepdesk Android app.')),
      );
    }
  }
}
