import 'package:flutter/material.dart';

import '../../foundation/icons/d_icons.dart';
import '../../theme/d_icon.dart';
import '../foundation/tokens.dart';

/// A decorative way-forward mark inside a row that owns navigation.
/// It has no independent focus, semantics, or activation target.
class DNavigationPill extends StatelessWidget {
  const DNavigationPill({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(DRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: DIconGlyphTheme(
            scale: 1,
            child: Transform.flip(
              flipX: Directionality.of(context) == TextDirection.ltr,
              child: DIcon(
                DIcons.arrowLeft,
                size: MediaQuery.textScalerOf(context).scale(11),
                color: tokens.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
