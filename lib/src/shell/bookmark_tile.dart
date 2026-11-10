import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/palette_contrast.dart';
import '../theme/discourse_typography.dart';

/// A row of the Bookmarks page, drawn alike for a post, topic, chat message,
/// page or category: a disc tinted by what it points at, a title of up to two
/// lines, and one muted line of [details].
///
/// Every row stands three points in from its start edge, which is where an
/// expired reminder draws its accent, so the accent never covers the disc.
class BookmarkTile extends StatelessWidget {
  const BookmarkTile({
    super.key,
    required this.icon,
    required this.title,
    required this.details,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
    this.expired = false,
    this.padding,
  });

  final DIconData icon;
  final String title;
  final String details;
  final String semanticLabel;
  final VoidCallback onPressed;

  /// The category or channel color; muted when the bookmark has none.
  final Color? color;
  final bool expired;

  /// Replaces the page's own insets where the tile sits in a padded menu.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final tint = color ?? tokens.mutedForeground;
    return DItem(
      shape: DItemShape.fullWidth,
      padding: padding ?? const EdgeInsetsDirectional.fromSTEB(3, 12, 0, 14),
      gap: 10,
      selectionStyle: DItemSelectionStyle.leadingAccent,
      selected: expired,
      showSelectionIndicator: false,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      children: [
        DItemMedia(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: mixInto(tokens.background, tint, .25),
            ),
            child: SizedBox.square(
              dimension: 34,
              child: Center(
                child: DIcon(
                  icon,
                  size: 14,
                  color: mixInto(tokens.foreground, tint, .5),
                ),
              ),
            ),
          ),
        ),
        DItemContent(
          spacing: 0,
          children: [
            DItemTitle(
              maxLines: 2,
              child: ExcludeSemantics(child: Text(title)),
            ),
            ExcludeSemantics(
              child: Text(
                details,
                style: TextStyle(
                  fontSize: DiscourseTypography.preview,
                  height: DiscourseTypography.lineHeightSmall,
                  color: tokens.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
