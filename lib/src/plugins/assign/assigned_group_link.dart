import 'package:flutter/foundation.dart';

import 'assigned_group.dart';

/// The Assign group-tab URL which represents assignments made directly to the
/// group named by the route.
@immutable
final class AssignedGroupLink {
  const AssignedGroupLink({
    required this.uri,
    required this.groupName,
    required this.filter,
  });

  final Uri uri;
  final String groupName;
  final AssignedGroupFilter filter;

  static const int maximumUrlLength = 2048;

  /// Parses `/g/:group/assigned` and each Assign-owned filter below it.
  static AssignedGroupLink? parse(String url) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;

    final segments = [...uri.pathSegments];
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    if (segments.length < 3 ||
        segments.length > 4 ||
        segments.any((segment) => segment.isEmpty)) {
      return null;
    }
    if (segments[0] != 'g' || segments[2] != 'assigned') return null;

    final groupName = segments[1];
    if (groupName.contains('/') || groupName.contains('\\')) return null;
    final segment = segments.length == 3 ? 'everyone' : segments[3];
    final AssignedGroupFilter filter;
    if (segment == 'everyone') {
      filter = const AssignedGroupFilter.everyone();
    } else if (segment == groupName) {
      filter = const AssignedGroupFilter.directGroup();
    } else {
      try {
        filter = AssignedGroupFilter.member(segment);
      } on ArgumentError {
        return null;
      }
    }
    return AssignedGroupLink(uri: uri, groupName: groupName, filter: filter);
  }

  /// Assign's topic-list endpoint for the group's direct assignments.
  String get feedPath =>
      '/topics/group-topics-assigned/'
      '${Uri.encodeComponent(groupName)}.json?direct=true';
}
