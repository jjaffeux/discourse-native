import 'package:flutter/foundation.dart';

/// The Assign group-tab URL which represents assignments made directly to the
/// group named by the route.
@immutable
final class AssignedGroupLink {
  const AssignedGroupLink({required this.uri, required this.groupName});

  final Uri uri;
  final String groupName;

  static const int maximumUrlLength = 2048;

  /// Parses only `/g/:group/assigned/:group`.
  ///
  /// Assign also owns `/everyone` and member-name filters. Those have
  /// different query semantics, so they stay in the browser until native
  /// screens explicitly support them.
  static AssignedGroupLink? parse(String url) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;

    final segments = [...uri.pathSegments];
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    if (segments.length != 4 || segments.any((segment) => segment.isEmpty)) {
      return null;
    }
    if (segments[0] != 'g' || segments[2] != 'assigned') return null;

    final groupName = segments[1];
    if (groupName != segments[3] || groupName.contains('/')) return null;
    return AssignedGroupLink(uri: uri, groupName: groupName);
  }

  /// Assign's topic-list endpoint for the group's direct assignments.
  String get feedPath =>
      '/topics/group-topics-assigned/'
      '${Uri.encodeComponent(groupName)}.json?direct=true';
}
