import 'package:flutter/material.dart';

import 'adaptive_dialog_action.dart';
import 'external_link.dart';

Uri illegalContentMailtoUri({
  required String email,
  required String topicTitle,
  required String postUrl,
}) => Uri(
  scheme: 'mailto',
  path: email,
  queryParameters: {
    'subject': 'Illegal content: $topicTitle',
    'body': 'This post $postUrl contains illegal content.',
  },
);

/// Explains anonymous reporting before handing the pre-filled report to the
/// platform mail application.
Future<void> showAnonymousIllegalContentDialog({
  required BuildContext context,
  required String email,
  required String topicTitle,
  required String postUrl,
}) async {
  final send = await showDiscourseDialog<bool>(
    context: context,
    builder: (dialogContext) => DiscourseAlertDialog(
      title: const Text('Report illegal content'),
      content: const Text(
        'This site accepts illegal-content reports by email. Your mail '
        'application will open with the post link and subject filled in.',
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        AdaptiveDialogAction(
          kind: AdaptiveDialogActionKind.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Open email'),
        ),
      ],
    ),
  );
  if (send != true || !context.mounted) return;

  final uri = illegalContentMailtoUri(
    email: email,
    topicTitle: topicTitle,
    postUrl: postUrl,
  );
  final opened = await openExternalLink(uri.toString());
  if (!opened && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text("Couldn't open a mail application.")),
    );
  }
}
