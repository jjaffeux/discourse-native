import 'package:flutter/widgets.dart';

import '../plugin_api/plugin_icon_catalog.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'json.dart';

typedef SidebarRowDecorationBuilder =
    Widget Function(BuildContext context, double size);

@immutable
class SidebarBadge {
  const SidebarBadge.count(this.count) : dot = false, urgent = false;
  const SidebarBadge.dot({this.urgent = false}) : count = 0, dot = true;

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
    this.prefixBuilder,
    this.labelSuffixBuilder,
    this.semanticDescription,
    this.iconColor,
    this.routeColor,
    this.prefixBadgeIcon,
    this.badge,
    this.onTap,
    this.trailingLabel,
    this.indent = 0,
    this.enabled = true,
    this.trailingIcon,
    this.onSecondaryTap,
    this.hoverActionBuilder,
    this.onLongPress,
    this.url,
    this.feedPath,
  });

  final String id;
  final String label;
  final DIconData icon;

  final Color? color;

  /// The parent category's colour, for the split swatch core draws beside a
  /// subcategory. [color] remains the child category's own colour.
  final Color? parentColor;

  /// Bare name, resolved against the site's custom emoji and artwork set.
  final String? emoji;

  final String? avatarUrl;

  /// Keeps live feature records out of this navigation DTO.
  final SidebarRowDecorationBuilder? prefixBuilder;

  final SidebarRowDecorationBuilder? labelSuffixBuilder;

  final String? semanticDescription;

  /// Distinct from [color], which draws a category *swatch* in the icon's
  /// place.
  final Color? iconColor;

  /// Icon- and emoji-style categories still tint the list they open, but must
  /// leave [color] null or the sidebar would replace their artwork with a
  /// square swatch.
  final Color? routeColor;

  final DIconData? prefixBadgeIcon;

  /// Null delegates the live badge lookup to the shell.
  final SidebarBadge? badge;

  final VoidCallback? onTap;

  final String? trailingLabel;
  final int indent;
  final bool enabled;
  final DIconData? trailingIcon;
  final VoidCallback? onSecondaryTap;

  final WidgetBuilder? hoverActionBuilder;

  final void Function(BuildContext context)? onLongPress;

  final String? url;

  final String? feedPath;
}

@immutable
class SidebarSection {
  const SidebarSection({
    required this.id,
    required this.title,
    required this.destinations,
    this.moreDestinations = const [],
    this.showHeader = true,
    this.collapsible = true,
    this.actionIcon,
    this.actionLabel,
    this.onAction,
  }) : assert(showHeader || !collapsible);

  /// Core's hidden `max_sidebar_section_links` setting is 50 and is enforced
  /// when custom sections are created or updated.
  static const int maximumCustomLinks = 50;

  final String id;

  /// Built-in sections have `section_type` and are already supplied locally.
  static SidebarSection? customFromJson(
    Map<String, dynamic> json, {
    required int index,
    IconNameDecoder icons = const CoreIconNameDecoder(),
  }) {
    if (json['section_type'] != null) return null;
    final title = jsonText(json['title']);
    if (title == null) return null;

    final sectionId = jsonIntOrNull(json['id']) ?? index;
    final destinations = <SidebarDestination>[];
    var linkIndex = 0;
    for (final rawLink in jsonArray(json['links']).take(maximumCustomLinks)) {
      if (rawLink is! Map<String, dynamic>) {
        linkIndex++;
        continue;
      }
      final link = rawLink;
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
          icon: icons.iconNamed(iconName, fallback: DIcons.link),
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

  /// Core promotes the active secondary link into the section itself so the
  /// current route stays visible without making every secondary destination a
  /// permanent sidebar row.
  final List<SidebarDestination> moreDestinations;

  final bool showHeader;

  final bool collapsible;

  final DIconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;
}
