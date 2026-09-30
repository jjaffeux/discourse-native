import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

/// Mobile composer form composition with independently scrolling fields.
class ComposerSheetLayout extends StatelessWidget {
  const ComposerSheetLayout({
    super.key,
    required this.title,
    required this.child,
    required this.onApply,
    this.onRemove,
    this.removeLabel,
    this.error,
  }) : assert(onRemove == null || removeLabel != null);

  final String title;
  final Widget child;
  final VoidCallback onApply;
  final VoidCallback? onRemove;
  final String? removeLabel;
  final Widget? error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DSheetDragRegion(
        child: DSheetHeader(
          children: [
            Row(
              children: [
                Expanded(
                  child: DSheetTitle(
                    child: DText(
                      title,
                      variant: DTextVariant.h4,
                      headingLevel: 1,
                    ),
                  ),
                ),
                const SizedBox(width: DSpacing.md),
                DSheetClose<void>(
                  builder: (context, close) => DButton.iconOnly(
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
      ),
      Expanded(child: SingleChildScrollView(child: child)),
      const DSeparator(),
      DSheetFooter(
        children: [
          ?error,
          DButton(
            label: Text(context.l10n.apply),
            onPressed: onApply,
            variant: DButtonVariant.primary,
            expanded: true,
          ),
          if (onRemove case final remove?)
            DButton(
              label: Text(removeLabel!),
              onPressed: remove,
              variant: DButtonVariant.destructive,
              expanded: true,
            ),
        ],
      ),
    ],
  );
}
