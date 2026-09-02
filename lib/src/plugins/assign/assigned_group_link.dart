import 'package:flutter/foundation.dart';

import '../../models/discourse_instance.dart';
import 'assigned_group.dart';

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

  /// [siteUrl] names the forum the link belongs to, so a subfolder site's
  /// prefix is required and skipped before the route is read.
  static AssignedGroupLink? parse(String url, {String? siteUrl}) {
    if (url.isEmpty || url.length > maximumUrlLength) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isNotEmpty) return null;

    final within = siteUrl == null
        ? uri.pathSegments
        : DiscourseInstance.pathSegmentsWithin(siteUrl, uri);
    if (within == null) return null;
    final segments = [...within];
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

  String get feedPath =>
      '/topics/group-topics-assigned/'
      '${Uri.encodeComponent(groupName)}.json?direct=true';
}
