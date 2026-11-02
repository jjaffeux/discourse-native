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
      trailing: DSheetClose<void>(
        builder: (context, close) => DSheetHeaderAction.close(
          buttonKey: closeButtonKey,
          onPressed: close,
          tooltip: context.l10n.close,
        ),
      ),
      children: [
        DSheetTitle(
          child: DText(title, variant: DTextVariant.h4, headingLevel: 1),
        ),
      ],
    ),
  );
}
