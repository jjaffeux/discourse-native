import 'package:flutter/widgets.dart';

import '../theme/d_icon.dart';

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
/// already have the answer in hand; see `SitePlugin.sidebarSections`.
@immutable
class SidebarDestination {
  const SidebarDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
    this.emoji,
    this.avatarUrl,
    this.iconColor,
    this.badge,
  });

  final String id;
  final String label;
  final DIconData icon;

  /// Set for entries Discourse renders with a category badge rather than an
  /// icon; when it is null the [icon] is drawn instead.
  final Color? color;

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

  /// What this entry already knows about what has not been read, or null — the
  /// ordinary case — to ask `ShellController.sidebarBadgeFor` instead.
  final SidebarBadge? badge;
}

/// A titled group of destinations, e.g. "Categories" or "Chat".
@immutable
class SidebarSection {
  const SidebarSection({required this.title, required this.destinations});

  final String title;
  final List<SidebarDestination> destinations;
}
