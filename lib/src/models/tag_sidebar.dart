import '../theme/d_icons.dart';
import 'sidebar.dart';
import 'sidebar_tag.dart';
import 'topic_tag.dart';

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

SidebarDestination? buildTagDestination(SidebarTag tag, {String? username}) {
  final pmUsername = username?.trim();
  if (tag.pmOnly && (pmUsername?.isEmpty ?? true)) return null;

  final feedPath = tag.pmOnly
      ? _privateMessageTagFeedPath(tag, pmUsername!)
      : _publicTagFeedPath(tag);

  return SidebarDestination(
    id: _topicTagDestinationId(
      feedPath: feedPath,
      id: tag.id,
      privateMessage: tag.pmOnly,
    ),
    label: tag.name,
    icon: DIcons.tag,
    feedPath: feedPath,
  );
}

SidebarDestination? buildTopicTagDestination(
  TopicTag tag, {
  String? username,
  bool privateMessage = false,
}) {
  final name = tag.name.trim();
  if (name.isEmpty) return null;

  final id = tag.id;
  final validId = id != null && id > 0 ? id : null;
  final private = privateMessage || tag.pmOnly;
  final pmUsername = username?.trim();
  if (private && (pmUsername?.isEmpty ?? true)) return null;

  final slug = tag.slug?.trim();
  final feedPath = private
      ? _privateMessageTagFeedPathFor(name, pmUsername!)
      : _publicTagFeedPathFor(
          slug == null || slug.isEmpty ? name : slug,
          validId,
        );
  return SidebarDestination(
    id: _topicTagDestinationId(
      feedPath: feedPath,
      id: validId,
      privateMessage: private,
    ),
    label: name,
    icon: DIcons.tag,
    feedPath: feedPath,
  );
}

String _topicTagDestinationId({
  required String feedPath,
  required int? id,
  required bool privateMessage,
}) {
  if (id == null) return 'list-$feedPath';
  return '${privateMessage ? 'pm-tag' : 'tag'}-$id';
}

String _publicTagFeedPath(SidebarTag tag) {
  return _publicTagFeedPathFor(tag.slug, tag.id);
}

String _publicTagFeedPathFor(String rawSlug, int? id) {
  final slug = _decodedPathSegment(rawSlug);
  final uri = Uri(
    pathSegments: [
      'tag',
      if (id == null) '$slug.json' else ...[slug, '$id.json'],
    ],
  );
  return '/${uri.toString()}';
}

String _privateMessageTagFeedPath(SidebarTag tag, String username) {
  return _privateMessageTagFeedPathFor(tag.name, username);
}

String _privateMessageTagFeedPathFor(String name, String username) {
  final uri = Uri(
    pathSegments: ['topics', 'private-messages-tags', username, '$name.json'],
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
