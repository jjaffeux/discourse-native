import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// One quote surface shared by reading and composing.
///
/// The optional [header] owns attribution and navigation. [trailing] accepts
/// a Native action; its owner supplies the callback. The leading rail is
/// decorative, with no independent semantics or hit target.
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
        border: BorderDirectional(
          start: BorderSide(color: tokens.primary, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 1, 0, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null || trailing != null) ...[
              Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      child: header ?? const SizedBox.shrink(),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 7),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 5),
            ],
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: DiscourseTypography.compact,
                color: tokens.mutedForeground,
                height: DiscourseTypography.lineHeightSmall,
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
