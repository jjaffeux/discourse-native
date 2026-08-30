import '../theme/d_icons.dart';
import 'sidebar.dart';
import 'sidebar_tag.dart';

/// Builds the native equivalent of core's built-in Tags section.
///
/// [display] is the server-owned decision to expose the section. An exposed
/// section remains present when no individual tags are available so its
/// All tags destination does not disappear during an empty response.
SidebarSection? buildTagSidebarSection({
  required List<SidebarTag> tags,
  required bool display,
  String? username,
}) {
  if (!display) return null;

  return SidebarSection(
    id: 'tags',
    title: 'Tags',
    destinations: List.unmodifiable([
      for (final tag in tags) ?buildTagDestination(tag, username: username),
      const SidebarDestination(
        id: 'all-tags',
        label: 'All tags',
        icon: DIcons.list,
      ),
    ]),
  );
}

/// The native list destination represented by one tag record.
///
/// A private-message tag has no usable route without an account name, so it is
/// omitted rather than exposing a destination the server cannot resolve.
SidebarDestination? buildTagDestination(SidebarTag tag, {String? username}) {
  final pmUsername = username?.trim();
  if (tag.pmOnly && (pmUsername?.isEmpty ?? true)) return null;

  return SidebarDestination(
    id: 'tag-${tag.id}',
    label: tag.name,
    icon: DIcons.tag,
    feedPath: tag.pmOnly
        ? _privateMessageTagFeedPath(tag, pmUsername!)
        : _publicTagFeedPath(tag),
  );
}

String _publicTagFeedPath(SidebarTag tag) {
  final slug = _decodedPathSegment(tag.slug);
  final uri = Uri(pathSegments: ['tag', slug, '${tag.id}.json']);
  return '/${uri.toString()}';
}

String _privateMessageTagFeedPath(SidebarTag tag, String username) {
  final uri = Uri(
    pathSegments: [
      'topics',
      'private-messages-tags',
      username,
      '${tag.name}.json',
    ],
  );
  return '/${uri.toString()}';
}

String _decodedPathSegment(String value) {
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  }
}
