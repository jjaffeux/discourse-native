import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            start: 11,
            top: 11,
            bottom: 11,
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
            padding: const EdgeInsetsDirectional.fromSTEB(25, 11, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (header != null || trailing != null) ...[
                  Row(
                    children: [
                      Expanded(child: header ?? const SizedBox.shrink()),
                      const SizedBox(width: 7),
                      ExcludeSemantics(
                        child: IgnorePointer(
                          child: DIcon(
                            DIcons.quoteRight,
                            size: 13,
                            color: tokens.mutedForeground.withValues(alpha: .6),
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
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
