import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
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
      title: const DAlertTitle(child: Text('Some tags were removed')),
      description: DAlertDescription(child: Text(message)),
      action: DAlertAction(
        child: DButton.iconOnly(
          icon: const DIcon(DIcons.xmark, size: 14),
          tooltip: 'Dismiss tag notice',
          variant: DButtonVariant.flatClose,
          size: DButtonSize.small,
          onPressed: onDismiss,
        ),
      ),
    ),
  );
}
