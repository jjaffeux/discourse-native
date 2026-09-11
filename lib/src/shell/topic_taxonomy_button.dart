import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';

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
    this.tooltip,
    this.focusNode,
    this.expanded = false,
  });

  final DButtonSize size;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double maximumWidth;
  final Key? buttonKey;
  final Widget? icon;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool expanded;

  @override
  Widget build(BuildContext context) => IntrinsicWidth(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maximumWidth),
      child: DButton(
        key: buttonKey,
        size: size,
        label: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            const DIcon(DIcons.chevronDown, size: 16),
          ],
        ),
        icon: icon,
        tooltip: tooltip,
        semanticLabel: semanticLabel,
        onPressed: onPressed,
        focusNode: focusNode,
        hasPopup: true,
        expanded: expanded,
        alignment: AlignmentDirectional.centerStart,
        variant: DButtonVariant.outline,
      ),
    ),
  );
}
