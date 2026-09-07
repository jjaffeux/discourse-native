import 'package:flutter/foundation.dart';

import 'found_group.dart';
import 'json.dart';

/// Optional group identity supplied by Discourse's UserFlairMixin.
///
/// A flair identifies a group, not necessarily an AI bot. Older servers omit
/// these fields; a group with neither an image/icon nor a background is invisible.
@immutable
class UserFlair {
  const UserFlair({
    required this.groupId,
    this.name,
    this.url,
    this.color,
    this.backgroundColor,
  });

  static UserFlair? fromJson(Object? value, String siteUrl) {
    if (value is! Map<String, dynamic>) return null;
    final groupId = jsonIntOrNull(value['flair_group_id']);
    final url = resolveFlairUrl(jsonText(value['flair_url']), siteUrl);
    final backgroundColor = jsonText(value['flair_bg_color']);
    if (groupId == null || groupId <= 0) return null;
    if (url == null && backgroundColor == null) return null;
    return UserFlair(
      groupId: groupId,
      name: jsonText(value['flair_name']),
      url: url,
      color: jsonText(value['flair_color']),
      backgroundColor: backgroundColor,
    );
  }

  final int groupId;
  final String? name;
  final String? url;
  final String? color;
  final String? backgroundColor;

  String get label => name ?? 'Group flair';

  @override
  bool operator ==(Object other) =>
      other is UserFlair &&
      other.groupId == groupId &&
      other.name == name &&
      other.url == url &&
      other.color == color &&
      other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(groupId, name, url, color, backgroundColor);
}
