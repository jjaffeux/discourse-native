import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/d_icons.dart';

class ComposerTagRemovalNotice extends StatelessWidget {
  const ComposerTagRemovalNotice({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: DAlert(
      icon: const DIcon(DIcons.tag),
      title: DAlertTitle(child: Text(context.l10n.someTagsWereRemoved)),
      description: DAlertDescription(child: Text(message)),
      action: DAlertAction(
        child: DButton.iconOnly(
          icon: const DIcon(DIcons.xmark),
          tooltip: context.l10n.dismissTagNotice,
          variant: DButtonVariant.ghost,
          size: DButtonSize.regular,
          onPressed: onDismiss,
        ),
      ),
    ),
  );
}
