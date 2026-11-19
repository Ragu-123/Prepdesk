import 'package:flutter/material.dart';
import '../data/database_service.dart';
import '../services/app_update_service.dart';
import '../utils/url_helper.dart';

const prepdeskRepositoryUrl = 'https://github.com/${AppUpdateService.defaultGithubRepo}';

Future<bool> countLaunchForSupportPrompt() async {
  final db = DatabaseService.instance;
  if (await db.getConfig('github_support_done') == '1') return false;
  final launches = (int.tryParse(await db.getConfig('github_support_launches') ?? '') ?? 0) + 1;
  await db.setConfig('github_support_launches', '$launches');
  final next = int.tryParse(await db.getConfig('github_support_next') ?? '') ?? 3;
  return launches >= next;
}

Future<void> showGithubSupportPrompt(BuildContext context) async {
  final star = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Enjoying Prepdesk?', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('You can support the project by starring it on GitHub.'),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.star_outline_rounded), label: const Text('Star on GitHub')),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Maybe later')),
      ]),
    )),
  );
  final db = DatabaseService.instance;
  if (star == true) {
    await db.setConfig('github_support_done', '1');
    await openExternalUrl(prepdeskRepositoryUrl);
  } else {
    final launches = int.tryParse(await db.getConfig('github_support_launches') ?? '') ?? 0;
    await db.setConfig('github_support_next', '${launches + 20}');
  }
}
