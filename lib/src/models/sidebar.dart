import 'package:flutter/widgets.dart';

/// A single tappable entry in the instance sidebar.
///
/// [color] is set for entries that Discourse renders with a category badge
/// rather than an icon; when it is null the [icon] is drawn instead.
///
/// Badge counts are deliberately not here — they are live state, read from
/// `ShellController.sidebarBadgeFor`.
@immutable
class SidebarDestination {
  const SidebarDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color? color;
}

/// A titled group of destinations, e.g. "Categories" or "Chat".
@immutable
class SidebarSection {
  const SidebarSection({required this.title, required this.destinations});

  final String title;
  final List<SidebarDestination> destinations;
}
