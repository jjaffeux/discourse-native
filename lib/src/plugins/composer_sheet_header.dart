import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

class ComposerSheetHeader extends StatelessWidget {
  const ComposerSheetHeader({
    super.key,
    required this.title,
    this.closeButtonKey,
  });

  final String title;
  final Key? closeButtonKey;

  @override
  Widget build(BuildContext context) => DSheetDragRegion(
    child: DSheetHeader(
      children: [
        Row(
          children: [
            Expanded(
              child: DSheetTitle(
                child: DText(title, variant: DTextVariant.h4, headingLevel: 1),
              ),
            ),
            const SizedBox(width: DSpacing.md),
            DSheetClose<void>(
              builder: (context, close) => DButton.iconOnly(
                key: closeButtonKey,
                onPressed: close,
                size: DButtonSize.small,
                shape: DButtonShape.pill,
                variant: DButtonVariant.secondary,
                icon: const Icon(Icons.close),
                tooltip: context.l10n.close,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
