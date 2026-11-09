import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../foundation/icons/d_native_icons.dart';
import '../theme/discourse_typography.dart';

/// What a picture in a post draws once it cannot load.
///
/// Fills a slot that already has its size. A slot that names none, such as an
/// image without declared dimensions, gets a 4:3 box capped at the width of a
/// post's media.
class BrokenImage extends StatelessWidget {
  const BrokenImage({super.key, this.radius = defaultRadius});

  static const double defaultRadius = 8;

  /// Zero inside a gallery, whose frame rounds the group.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final label = context.l10n.brokenImage;
    final color = tokens.mutedForeground;

    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: DCard(
              dashedBorder: true,
              spacing: 0,
              backgroundColor: tokens.raisedBackground,
              borderRadius: BorderRadius.circular(radius),
              child: Expanded(
                // A small grid tile scales the content rather than clipping it.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DIcon(DNativeIcons.image, size: 18, color: color),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: DiscourseTypography.preview,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
