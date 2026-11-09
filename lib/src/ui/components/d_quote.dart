import 'package:flutter/material.dart';

import '../../foundation/icons/d_icons.dart';
import '../../theme/d_icon.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// One quote surface shared by reading and composing.
///
/// The optional [header] owns attribution and navigation. [trailing] accepts
/// a Native action; its owner supplies the callback. The accent and quotation
/// mark are decorative, with no independent semantics or hit targets.
class DQuote extends StatelessWidget {
  const DQuote({super.key, this.header, this.trailing, required this.child});

  final Widget? header;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final nested = context.findAncestorWidgetOfExactType<DQuote>() != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.raisedBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            start: nested ? 0 : 11,
            top: nested ? 0 : 11,
            bottom: nested ? 0 : 11,
            width: 3,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.primary,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ),
          Padding(
            padding: nested
                ? const EdgeInsetsDirectional.only(start: 12)
                : const EdgeInsetsDirectional.fromSTEB(25, 11, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null || trailing != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DefaultTextStyle.merge(
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: tokens.mutedForeground),
                          child: header ?? const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 7),
                      ExcludeSemantics(
                        child: IgnorePointer(
                          child: DIcon(
                            DIcons.quoteRight,
                            size: 13,
                            color: tokens.subtleMark,
                          ),
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 7),
                        trailing!,
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: DiscourseTypography.base,
                    height: DiscourseTypography.lineHeightContent,
                    color: tokens.mutedForeground,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
