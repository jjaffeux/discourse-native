import 'package:flutter/widgets.dart';

import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'json.dart';

/// What a sidebar row says about what has not been read.
///
/// A count and a dot are different claims rather than two renderings of one. A
/// topic list can say *how many*, because the number is small, meaningful and
/// slow-moving. A chat channel deliberately does not — Discourse draws a dot
/// there because the count in a busy channel moves faster than it is worth
/// reading, and "someone spoke" is the whole message.
///
/// [urgent] separates what is addressed to the reader from what merely happened
/// near them, which is the distinction `NotificationTotals.badge` already makes
/// for the rail.
@immutable
class SidebarBadge {
  const SidebarBadge.count(this.count) : dot = false, urgent = false;
  const SidebarBadge.dot({this.urgent = false}) : count = 0, dot = true;

  /// Nothing to say. The value a row with no unread anything carries, so that
  /// nothing downstream has to hold a nullable badge as well as an invisible
  /// one.
  static const SidebarBadge none = SidebarBadge.count(0);

  final int count;
  final bool dot;
  final bool urgent;

  bool get isVisible => dot || count > 0;

  @override
  bool operator ==(Object other) =>
      other is SidebarBadge &&
      other.count == count &&
      other.dot == dot &&
      other.urgent == urgent;

  @override
  int get hashCode => Object.hash(count, dot, urgent);
}

/// A single tappable entry in the instance sidebar.
///
/// The prefix is whichever of [avatarUrl], [emoji], [color] and [icon] the
/// entry has, in that order — a face beats a picture beats a category badge
/// beats a glyph. [icon] is the only one always present, so there is always
/// something to draw.
///
/// Badge counts for core's own destinations are deliberately not here — they
/// are live state, read from `ShellController.sidebarBadgeFor`, because those
/// sections are a `const` getter on an immutable model and cannot carry a
/// moving number. [badge] is for entries built fresh from live state, which
/// already have the answer in hand; see `SidebarPlugin.sidebarSections`.
@immutable
class SidebarDestination {
  const SidebarDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
    this.parentColor,
    this.emoji,
    this.avatarUrl,
    this.iconColor,
    this.routeColor,
    this.prefixBadgeIcon,
    this.badge,
    this.onTap,
    this.children = const [],
    this.trailingLabel,
    this.indent = 0,
    this.enabled = true,
    this.trailingIcon,
    this.onSecondaryTap,
    this.url,
    this.feedPath,
  });

  final String id;
  final String label;
  final DIconData icon;

  /// Set for entries Discourse renders with a category badge rather than an
  /// icon; when it is null the [icon] is drawn instead.
  final Color? color;

  /// The parent category's colour, for the split swatch core draws beside a
  /// subcategory. [color] remains the child category's own colour.
  final Color? parentColor;

  /// The bare name of an emoji to draw in place of [icon] — `bug`, not
  /// `:bug:`.
  ///
  /// A name and not a URL, so the tile resolves it through
  /// `ShellController.emojiUrlFor` where it is drawn — which is what makes a
  /// site's custom emoji and its chosen set apply here the way they do inside a
  /// post — and so the fallback text writes itself.
  final String? emoji;

  /// One account's face, for a row that stands for a person rather than a
  /// place.
  final String? avatarUrl;

  /// What tints [icon], for an entry the site gave a colour but not a badge.
  ///
  /// Distinct from [color], which draws a category *swatch* in the icon's
  /// place. A chat channel in a category is a channel and not the category, so
  /// it keeps its own glyph and borrows only the colour — which is what
  /// Discourse's own sidebar does with `prefixColor`.
  final Color? iconColor;

  /// The colour carried into the content header when it differs from [color].
  ///
  /// Icon- and emoji-style categories still tint the list they open, but must
  /// leave [color] null or the sidebar would replace their artwork with a
  /// square swatch.
  final Color? routeColor;

  /// A small glyph overlaid on the prefix, such as core's restricted-category
  /// lock. This is separate from [badge], which describes unread activity at
  /// the trailing edge of the row.
  final DIconData? prefixBadgeIcon;

  /// What this entry already knows about what has not been read, or null — the
  /// ordinary case — to ask `ShellController.sidebarBadgeFor` instead.
  final SidebarBadge? badge;

  /// An action row rather than ordinary content navigation.
  final VoidCallback? onTap;

  /// Non-navigation rows nested under this destination, such as people
  /// currently present in a voice room.
  final List<SidebarDestination> children;

  final String? trailingLabel;
  final int indent;
  final bool enabled;
  final DIconData? trailingIcon;
  final VoidCallback? onSecondaryTap;

  /// A site or external link this row opens, for destinations supplied by a
  /// custom Discourse sidebar section rather than a native app route.
  final String? url;

  /// The JSON topic-list route for a native destination discovered at runtime.
  /// Static routes such as Latest are resolved by the shell, while category
  /// destinations bring this path with them.
  final String? feedPath;
}

/// A group of destinations, usually under a title such as "Categories" or
/// "Chat".
@immutable
class SidebarSection {
  const SidebarSection({
    required this.id,
    required this.title,
    required this.destinations,
    this.showHeader = true,
    this.collapsible = true,
    this.actionIcon,
    this.actionLabel,
    this.onAction,
  }) : assert(showHeader || !collapsible);

  /// Stable identity used for presentation preferences such as collapsing.
  final String id;

  /// Reads one user-created section from `/sidebar_sections.json`.
  ///
  /// That route also returns Discourse's built-in Community section. A
  /// non-null `section_type` identifies those built-ins, which this app
  /// already supplies itself, so they are deliberately left out here.
  static SidebarSection? customFromJson(
    Map<String, dynamic> json, {
    required int index,
  }) {
    if (json['section_type'] != null) return null;
    final title = jsonText(json['title']);
    if (title == null) return null;

    final sectionId = jsonIntOrNull(json['id']) ?? index;
    final destinations = <SidebarDestination>[];
    var linkIndex = 0;
    for (final link in jsonObjects(json['links'])) {
      final name = jsonText(link['name']);
      final value = jsonText(link['value']);
      if (name == null || value == null) {
        linkIndex++;
        continue;
      }
      final linkId = jsonIntOrNull(link['id']) ?? linkIndex;
      final iconName = jsonText(link['icon']);
      destinations.add(
        SidebarDestination(
          id: 'custom-$sectionId-$linkId',
          label: name,
          icon: DIcons.byName[iconName] ?? DIcons.link,
          url: value,
        ),
      );
      linkIndex++;
    }

    return SidebarSection(
      id: 'custom-$sectionId',
      title: title,
      destinations: List.unmodifiable(destinations),
    );
  }

  final String title;
  final List<SidebarDestination> destinations;

  /// Whether the section title and its optional action are visible.
  ///
  /// A headerless section must also be non-collapsible because it has no
  /// visible control with which to reveal its destinations again.
  final bool showHeader;

  /// Whether the header can hide this section's destinations.
  final bool collapsible;

  final DIconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;
}
