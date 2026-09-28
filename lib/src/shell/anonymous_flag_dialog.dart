import 'package:discourse_native/l10n/strings.dart';
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
            'subject': appL10n.illegalContent((topicTitle).toString()),
            'body': appL10n.thisPostContainsIllegalContent(
              (postUrl).toString(),
            ),
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
      title: Text(appL10n.reportIllegalContent),
      content: Text(
        appL10n.thisSiteAcceptsIllegalContentReportsByEmailYourMailApplication,
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(appL10n.cancel),
        ),
        AdaptiveDialogAction(
          kind: AdaptiveDialogActionKind.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(appL10n.openEmail),
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
      appL10n.couldnTOpenAMailApplication,
      type: DToastType.error,
    );
  }
}
