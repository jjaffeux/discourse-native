import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'emoji.dart';
import 'open_link.dart';
import 'pill.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// What kind of thing a `#hashtag` names.
enum HashtagKind {
  category,
  tag;

  static HashtagKind? parse(String? type) => switch (type) {
    'category' => HashtagKind.category,
    'tag' => HashtagKind.tag,
    _ => null,
  };
}

/// How a hashtag draws its prefix, from the cooked anchor's `data-style-type`.
enum HashtagStyle {
  /// A colour swatch. What an ordinary category gets.
  square,
  icon,
  emoji;

  static HashtagStyle parse(String? style) => switch (style) {
    'icon' => HashtagStyle.icon,
    'emoji' => HashtagStyle.emoji,
    // Discourse's own default when the attribute is missing.
    _ => HashtagStyle.square,
  };
}

/// The icon a hashtag draws, by the name the site gave.
///
/// Falls back on the kind's own default rather than on nothing: `data-icon` is
/// whatever an admin picked in the category settings, and the sprite here holds
/// the icons this app draws rather than all of Font Awesome.
DIconData iconFor(String? icon, HashtagKind kind) {
  final named = icon == null ? null : DIcons.byName[icon];
  if (named != null) return named;
  return kind == HashtagKind.category ? DIcons.folder : DIcons.tag;
}

/// The colour swatch ahead of a category hashtag.
///
/// A subcategory is split down the middle — parent on the left, child on the
/// right — which is Discourse's `linear-gradient(-90deg, #child 50%, #parent
/// 50%)`: `-90deg` runs the line leftwards, so the *first* stop paints the
/// right half.
class CategorySquare extends StatelessWidget {
  const CategorySquare({
    super.key,
    required this.color,
    required this.size,
    this.parentColor,
  });

  /// Null when the category has not been fetched — see [HashtagPill]. Drawn in
  /// the same neutral Discourse uses before its own colours arrive.
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

/// One `#category` or `#tag`, drawn as a pill.
///
/// The cooked anchor carries everything about *what* the hashtag is —
/// `data-type`, `data-style-type`, `data-icon`, `data-emoji` — but nothing
/// about its colour. On the web that arrives in a generated stylesheet; here it
/// comes from the categories the shell already fetches, looked up by the
/// `data-id` the anchor carries. A hashtag drawn before they land, or on a site
/// whose category list was capped, keeps its label and its tap and draws a
/// neutral square — which is exactly what Discourse itself shows until its own
/// colours arrive.
class HashtagPill extends StatelessWidget {
  const HashtagPill({
    super.key,
    required this.label,
    required this.baseStyle,
    required this.kind,
    required this.style,
    this.href,
    this.recordId,
    this.icon,
    this.emoji,
    this.colorValues,
  });

  final String label;
  final TextStyle? baseStyle;
  final HashtagKind kind;
  final HashtagStyle style;

  final String? href;

  /// `data-id` — the category or tag id, which is how the colour is found.
  final int? recordId;

  final String? icon;
  final String? emoji;

  /// Colours the caller already has, ARGB, in `[parent, child]` order.
  ///
  /// The composer's path: it holds a `FoundHashtag` the site answered with, so
  /// it needs no category lookup — and could not do one anyway, since the
  /// identity store is keyed by id and a ref is not one. Null in cooked HTML,
  /// where [recordId] is what finds them.
  final List<int>? colorValues;

  @override
  Widget build(BuildContext context) {
    final target = href;
    return Pill(
      label: label,
      baseStyle: baseStyle,
      leading: _leading(context),
      // The label rather than the slug: Discourse writes the real name into
      // the anchor — `Parent > Child` for a subcategory — and that beats
      // un-slugging the URL once the list is open.
      onTap: target == null
          ? null
          : () => openLink(context, target, title: label),
    );
  }

  Widget _leading(BuildContext context) {
    final controller = ShellScope.maybeOf(context);
    final size = Pill.fontSizeFor(baseStyle);

    switch (style) {
      case HashtagStyle.emoji:
        final name = emoji;
        final siteUrl = controller?.currentInstance?.url;
        if (name == null || controller == null || siteUrl == null) {
          return _icon(context, size, null);
        }
        return EmojiImage(
          url: controller.emojiUrlFor(siteUrl, name),
          size: size * pillGlyph,
          alt: '',
        );

      case HashtagStyle.icon:
        return _icon(context, size, _categoryColor(controller));

      case HashtagStyle.square:
        // Only a category has a swatch. A tag has no colour of its own —
        // `TagHashtagDataSource` sends none — so it keeps its glyph.
        if (kind != HashtagKind.category) {
          return _icon(context, size, null);
        }
        final category = _category(controller);
        return Padding(
          padding: EdgeInsets.only(left: size * pillSquareInset),
          child: CategorySquare(
            size: size * pillSquare,
            color: _categoryColor(controller),
            parentColor: _parentColor(controller, category),
          ),
        );
    }
  }

  Widget _icon(BuildContext context, double size, Color? tint) => DIcon(
    iconFor(icon, kind),
    size: Pill.iconBoxFor(baseStyle),
    // A tag's glyph takes the pill's own text colour, the way Discourse leaves
    // it to inherit; a category's takes the category's.
    color: tint ?? Theme.of(context).colorScheme.onSurfaceVariant,
  );

  TopicCategory? _category(ShellController? controller) =>
      kind == HashtagKind.category ? controller?.categoryFor(recordId) : null;

  /// The category's own colour — the last of [colorValues] when the caller
  /// brought them, otherwise the store's, by id.
  Color? _categoryColor(ShellController? controller) {
    if (colorValues case final given? when given.isNotEmpty) {
      return Color(given.last);
    }
    final category = _category(controller);
    return category == null ? null : Color(category.colorValue);
  }

  Color? _parentColor(ShellController? controller, TopicCategory? category) {
    if (colorValues case final given?) {
      return given.length >= 2 ? Color(given.first) : null;
    }
    final parentId = category?.parentCategoryId;
    if (parentId == null) return null;
    final parent = controller?.categoryFor(parentId);
    return parent == null ? null : Color(parent.colorValue);
  }
}

/// Hands `<a class="hashtag-cooked">` to [HashtagPill], for
/// [HtmlWidget.customWidgetBuilder].
///
/// The `<svg>` inside the anchor is deliberately ignored. Discourse bakes the
/// *same* placeholder — `d-icon-square-full` — into every hashtag whatever its
/// type, and its own client throws that away and redraws from the `data-`
/// attributes. Reading it would draw a filled square for every tag on the site.
///
/// An unresolved hashtag arrives as `<span class="hashtag-raw">` and is left
/// alone, exactly as Discourse leaves it: it is prose that looks like a
/// hashtag, and a pill would promise a place that is not there.
Widget? hashtagWidgetBuilder(dom.Element element, TextStyle? baseStyle) {
  if (element.localName != 'a') return null;
  if (!element.classes.contains('hashtag-cooked')) return null;

  final kind = HashtagKind.parse(element.attributes['data-type']);
  if (kind == null) return null;

  // The label span, and not `element.text`, which also picks up whatever
  // whitespace the icon placeholder contributes.
  final label =
      element.querySelector('span:not(.hashtag-icon-placeholder)')?.text.trim();
  if (label == null || label.isEmpty) return null;

  return InlineCustomWidget(
    child: HashtagPill(
      label: label,
      baseStyle: baseStyle,
      kind: kind,
      style: HashtagStyle.parse(element.attributes['data-style-type']),
      href: element.attributes['href'],
      recordId: int.tryParse(element.attributes['data-id'] ?? ''),
      icon: element.attributes['data-icon'],
      emoji: element.attributes['data-emoji'],
    ),
  );
}
