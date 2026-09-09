import 'package:flutter/material.dart';

import '../ui/components/d_toast.dart';

import 'adaptive_dialog_action.dart';
import 'external_link.dart';

Uri illegalContentMailtoUri({
  required String email,
  required String topicTitle,
  required String postUrl,
}) => Uri(
  scheme: 'mailto',
  path: email,
  // Mailto spaces must be %20; queryParameters uses form-style '+'.
  query:
      {
            'subject': 'Illegal content: $topicTitle',
            'body': 'This post $postUrl contains illegal content.',
          }.entries
          .map(
            (entry) =>
                '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
          )
          .join('&'),
);

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
    DToast.show(
      context,
      "Couldn't open a mail application.",
      type: DToastType.error,
    );
  }
}
