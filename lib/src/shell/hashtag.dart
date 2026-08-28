import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

import '../models/topic.dart';
import '../plugin_api/hashtag_kind.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'composer_autocomplete.dart';
import 'emoji.dart';
import 'open_link.dart';
import 'pill.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// Resolves core's two kinds, an installed plugin kind, or the neutral unknown
/// fallback without ever changing the server's type identity.
HashtagPresentation resolveHashtagPresentation(
  HashtagPresentationRequest request, {
  PluginHashtagPresentationResolver? pluginPresentation,
}) {
  switch (request.type) {
    case 'category':
      return HashtagPresentation.fromRequest(
        request,
        fallbackIcon: DIcons.folder,
        colorPolicy: HashtagColorPolicy.category,
      );
    case 'tag':
      return HashtagPresentation.fromRequest(
        request,
        fallbackIcon: DIcons.tag,
        colorPolicy: HashtagColorPolicy.none,
      );
  }

  final contributed = pluginPresentation?.call(request);
  return (contributed?.type == request.type ? contributed : null) ??
      HashtagPresentation.fromRequest(
        request,
        // Unknown targets are links, not tags. A known wire icon or emoji is
        // still honoured, and composer payload colours remain useful.
        fallbackIcon: DIcons.link,
        colorPolicy: HashtagColorPolicy.supplied,
      );
}

/// The icon a hashtag draws, by the name the site gave.
///
/// Falls back on the kind's own default rather than on nothing: `data-icon` is
/// whatever an admin picked in the category settings, and the sprite here holds
/// the icons this app draws rather than all of Font Awesome.
DIconData iconFor(String? icon, DIconData fallback) {
  final named = icon == null ? null : DIcons.byName[icon];
  return named ?? fallback;
}

/// Maps the same resolved policy used by a pill into autocomplete artwork.
SuggestionArt hashtagSuggestionArt(
  HashtagPresentation presentation, {
  required String Function(String emoji) resolveEmoji,
}) {
  final emoji = presentation.emoji;
  if (presentation.style == HashtagStyle.emoji) {
    return emoji == null
        ? ArtIcon(presentation.icon, fallback: presentation.fallbackIcon)
        : ArtImage(resolveEmoji(emoji));
  }
  if (presentation.style == HashtagStyle.square &&
      _drawsHashtagSquare(presentation)) {
    return ArtSquare(presentation.colorValues);
  }
  return ArtIcon(
    presentation.icon,
    colorValue: _hashtagColorValue(presentation),
    fallback: presentation.fallbackIcon,
  );
}

bool _drawsHashtagSquare(HashtagPresentation presentation) =>
    switch (presentation.colorPolicy) {
      HashtagColorPolicy.category => true,
      HashtagColorPolicy.supplied => presentation.colorValues.isNotEmpty,
      HashtagColorPolicy.none => false,
    };

int? _hashtagColorValue(HashtagPresentation presentation) =>
    presentation.colorPolicy == HashtagColorPolicy.none ||
        presentation.colorValues.isEmpty
    ? null
    : presentation.colorValues.last;

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

/// One server-confirmed hashtag target, drawn as a pill.
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
    required this.presentation,
    this.href,
    this.recordId,
    this.siteUrl,
  });

  final String label;
  final TextStyle? baseStyle;
  final HashtagPresentation presentation;

  final String? href;

  /// `data-id` — how core finds a category colour missing from cooked HTML.
  final int? recordId;

  /// The site that cooked this hashtag. Composer pills do not carry a link and
  /// may inherit the site currently owning the composer.
  final String? siteUrl;

  @override
  Widget build(BuildContext context) {
    final target = href;
    final controller = ShellScope.maybeRead(context);

    Widget pill(_HashtagShellPresentation shellPresentation) => Pill(
      label: label,
      baseStyle: baseStyle,
      leading: _leading(context, shellPresentation),
      // The label rather than the slug: Discourse writes the real name into
      // the anchor — `Parent > Child` for a subcategory — and that beats
      // un-slugging the URL once the list is open.
      onTap: target == null
          ? null
          : () => openLink(context, target, title: label, siteUrl: siteUrl),
    );

    if (controller == null) return pill(const _HashtagShellPresentation());
    return ShellSelector<_HashtagShellPresentation>(
      select: _shellPresentation,
      builder: (context, shellPresentation, child) => pill(shellPresentation),
    );
  }

  _HashtagShellPresentation _shellPresentation(ShellController controller) {
    final sourceSite = siteUrl ?? controller.currentInstance?.url;
    final category =
        presentation.colorPolicy == HashtagColorPolicy.category &&
            presentation.colorValues.isEmpty
        ? controller.categoryFor(recordId, siteUrl: sourceSite)
        : null;
    final parentId = category?.parentCategoryId;
    final parent = parentId == null
        ? null
        : controller.categoryFor(parentId, siteUrl: sourceSite);
    final emojiName = presentation.emoji;
    final emojiUrl =
        presentation.style == HashtagStyle.emoji &&
            emojiName != null &&
            sourceSite != null
        ? controller.emojiUrlFor(sourceSite, emojiName)
        : null;
    return _HashtagShellPresentation(
      category: category,
      parent: parent,
      emojiUrl: emojiUrl,
    );
  }

  Widget _leading(
    BuildContext context,
    _HashtagShellPresentation shellPresentation,
  ) {
    final size = Pill.fontSizeFor(baseStyle);

    switch (presentation.style) {
      case HashtagStyle.emoji:
        final url = shellPresentation.emojiUrl;
        if (url == null) {
          return _icon(context, size, null);
        }
        return EmojiImage(url: url, size: size * pillGlyph, alt: '');

      case HashtagStyle.icon:
        return _icon(context, size, _hashtagColor(shellPresentation));

      case HashtagStyle.square:
        if (!_drawsHashtagSquare(presentation)) {
          return _icon(context, size, null);
        }
        return Padding(
          padding: EdgeInsets.only(left: size * pillSquareInset),
          child: CategorySquare(
            size: size * pillSquare,
            color: _hashtagColor(shellPresentation),
            parentColor: _parentColor(shellPresentation),
          ),
        );
    }
  }

  Widget _icon(BuildContext context, double size, Color? tint) => DIcon(
    iconFor(presentation.icon, presentation.fallbackIcon),
    size: Pill.iconBoxFor(baseStyle),
    color: tint ?? Theme.of(context).colorScheme.onSurfaceVariant,
  );

  /// The last supplied colour, or a core category's colour resolved by id.
  Color? _hashtagColor(_HashtagShellPresentation shellPresentation) {
    if (presentation.colorPolicy == HashtagColorPolicy.none) return null;
    if (presentation.colorValues case final given when given.isNotEmpty) {
      return Color(given.last);
    }
    final category = shellPresentation.category;
    return category == null ? null : Color(category.colorValue);
  }

  Color? _parentColor(_HashtagShellPresentation shellPresentation) {
    if (presentation.colorPolicy == HashtagColorPolicy.none) return null;
    final given = presentation.colorValues;
    if (given.isNotEmpty) {
      return given.length >= 2 ? Color(given.first) : null;
    }
    final parent = shellPresentation.parent;
    return parent == null ? null : Color(parent.colorValue);
  }
}

@immutable
class _HashtagShellPresentation {
  const _HashtagShellPresentation({this.category, this.parent, this.emojiUrl});

  final TopicCategory? category;
  final TopicCategory? parent;
  final String? emojiUrl;

  @override
  bool operator ==(Object other) =>
      other is _HashtagShellPresentation &&
      other.category == category &&
      other.parent == parent &&
      other.emojiUrl == emojiUrl;

  @override
  int get hashCode => Object.hash(category, parent, emojiUrl);
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
Widget? hashtagWidgetBuilder(
  dom.Element element,
  TextStyle? baseStyle, {
  String? siteUrl,
  PluginHashtagPresentationResolver? pluginPresentation,
}) {
  if (element.localName != 'a') return null;
  if (!element.classes.contains('hashtag-cooked')) return null;

  final type = element.attributes['data-type'];
  if (type == null || type.trim().isEmpty) return null;

  // The label span, and not `element.text`, which also picks up whatever
  // whitespace the icon placeholder contributes.
  final label = element
      .querySelector('span:not(.hashtag-icon-placeholder)')
      ?.text
      .trim();
  if (label == null || label.isEmpty) return null;

  final presentation = resolveHashtagPresentation(
    HashtagPresentationRequest(
      type: type,
      style: HashtagStyle.parse(element.attributes['data-style-type']),
      icon: element.attributes['data-icon'],
      emoji: element.attributes['data-emoji'],
    ),
    pluginPresentation: pluginPresentation,
  );

  return InlineCustomWidget(
    child: HashtagPill(
      label: label,
      baseStyle: baseStyle,
      presentation: presentation,
      href: element.attributes['href'],
      recordId: int.tryParse(element.attributes['data-id'] ?? ''),
      siteUrl: siteUrl,
    ),
  );
}
