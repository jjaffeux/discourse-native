import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'composer_sheet_header.dart';

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
      ComposerSheetHeader(title: title),
      Expanded(child: SingleChildScrollView(child: child)),
      const DSeparator(),
      DSheetFooter(
        children: [
          ?error,
          Row(
            children: [
              if (onRemove case final remove?) ...[
                Expanded(
                  child: DButton(
                    label: Text(removeLabel!),
                    onPressed: remove,
                    variant: DButtonVariant.destructive,
                    expanded: true,
                  ),
                ),
                const SizedBox(width: DSpacing.controlGap),
              ],
              Expanded(
                child: DButton(
                  label: Text(context.l10n.apply),
                  onPressed: onApply,
                  variant: DButtonVariant.primary,
                  expanded: true,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
