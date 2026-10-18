import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_native_icons.dart';

class TopicTaxonomyButton extends StatelessWidget {
  const TopicTaxonomyButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    required this.maximumWidth,
    this.size = DButtonSize.regular,
    this.buttonKey,
    this.icon,
    this.focusNode,
    this.expanded = false,
    this.categoryColor,
    this.showChevron = false,
    this.quiet = true,
    this.quietSelected = false,
  });

  final DButtonSize size;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double maximumWidth;
  final Key? buttonKey;
  final Widget? icon;
  final FocusNode? focusNode;
  final bool expanded;
  final Color? categoryColor;
  final bool showChevron;
  final bool quiet;
  final bool quietSelected;

  @override
  Widget build(BuildContext context) => IntrinsicWidth(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maximumWidth),
      child: DButton(
        key: buttonKey,
        size: size,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (showChevron) ...[
              SizedBox(width: DControlStyle.contentGap(size)),
              DIcon(
                DNativeIcons.filterChevron,
                size: DControlStyle.chevronDimension(size),
              ),
            ],
          ],
        ),
        icon: icon,
        semanticLabel: semanticLabel,
        onPressed: onPressed,
        focusNode: focusNode,
        hasPopup: true,
        expanded: expanded,
        alignment: AlignmentDirectional.centerStart,
        variant: quiet
            ? (quietSelected
                  ? DButtonVariant.quietSelected
                  : DButtonVariant.quiet)
            : DButtonVariant.outline,
        backgroundColor: quiet
            ? null
            : categoryColor == null
            ? null
            : DTokens.of(
                context,
              ).categoryControlSurface(categoryColor!).background,
        foregroundColor: !quiet && categoryColor != null
            ? DTokens.of(
                context,
              ).categoryControlSurface(categoryColor!).foreground
            : null,
        borderColor: quiet
            ? null
            : categoryColor == null
            ? null
            : DTokens.of(context).categoryControlSurface(categoryColor!).border,
        interactiveBackgroundColor: quiet || categoryColor == null
            ? null
            : DTokens.of(context).categoryControlSurface(categoryColor!).hover,
      ),
    ),
  );
}
