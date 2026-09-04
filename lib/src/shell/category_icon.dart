import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'site_emoji_image.dart';

/// Renders the artwork configured for a Discourse category.
///
/// Category presentation is site-configurable: it may be a color square, an
/// icon, or an emoji. Keeping that decision here prevents individual category
/// surfaces from accidentally falling back to a square.
class CategoryIcon extends StatelessWidget {
  CategoryIcon({
    super.key,
    required TopicCategory category,
    TopicCategory? parentCategory,
    required this.size,
    this.squareSize,
    this.siteUrl,
  }) : color = Color(category.colorValue),
       parentColor = parentCategory == null
           ? null
           : Color(parentCategory.colorValue),
       styleType = category.styleType,
       icon = category.icon,
       emoji = category.emoji;

  const CategoryIcon.presentation({
    super.key,
    required this.color,
    required this.styleType,
    required this.size,
    this.icon,
    this.emoji,
    this.parentColor,
    this.squareSize,
    this.siteUrl,
  });

  final Color color;
  final Color? parentColor;
  final String styleType;
  final String? icon;
  final String? emoji;
  final double size;
  final double? squareSize;
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final emoji = this.emoji;
    final siteUrl = this.siteUrl;
    final Widget art;
    late final double extent;
    if (styleType == 'emoji' && emoji != null && siteUrl != null) {
      extent = size;
      art = SiteEmojiImage(siteUrl: siteUrl, name: emoji, size: size, alt: '');
    } else if (styleType == 'icon') {
      extent = size;
      art = DIcon(
        DIcons.byName[icon] ?? DIcons.folder,
        size: size,
        color: color,
      );
    } else {
      extent = squareSize ?? size * 0.75;
      art = CategorySquare(
        color: color,
        parentColor: parentColor,
        size: extent,
      );
    }

    return SizedBox.square(
      dimension: extent,
      child: Center(child: art),
    );
  }
}

class CategorySquare extends StatelessWidget {
  const CategorySquare({
    super.key,
    required this.color,
    required this.size,
    this.parentColor,
  });

  final Color? color;
  final Color? parentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = color ?? theme.colorScheme.onSurfaceVariant;
    final parent = parentColor;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: parent == null ? fill : null,
        gradient: parent == null
            ? null
            : LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [parent, parent, fill, fill],
                stops: const [0, 0.5, 0.5, 1],
              ),
        borderRadius: BorderRadius.circular(size * 0.15),
      ),
    );
  }
}
