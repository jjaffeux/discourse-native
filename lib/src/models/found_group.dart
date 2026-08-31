import 'package:flutter/foundation.dart';

import 'found_user.dart';
import 'json.dart';

@immutable
class FoundGroup {
  const FoundGroup({
    required this.name,
    this.fullName,
    this.flairUrl,
    this.flairColor,
    this.flairBackgroundColor,
  });

  factory FoundGroup.fromJson(Map<String, dynamic> json, String siteUrl) =>
      FoundGroup(
        name: jsonString(json['name']),
        fullName: jsonText(json['full_name']) ?? jsonText(json['display_name']),
        flairUrl: resolveFlairUrl(jsonText(json['flair_url']), siteUrl),
        flairColor: jsonText(json['flair_color']),
        flairBackgroundColor: jsonText(json['flair_bg_color']),
      );

  final String name;
  final String? fullName;
  final String? flairUrl;
  final String? flairColor;
  final String? flairBackgroundColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoundGroup &&
          other.name == name &&
          other.fullName == fullName &&
          other.flairUrl == flairUrl &&
          other.flairColor == flairColor &&
          other.flairBackgroundColor == flairBackgroundColor;

  @override
  int get hashCode =>
      Object.hash(name, fullName, flairUrl, flairColor, flairBackgroundColor);
}

String? resolveFlairUrl(String? value, String siteUrl) {
  if (value == null || value.isEmpty) return null;
  return value.contains('/') ? resolveAvatarUrl(value, siteUrl) : value;
}

@immutable
class FoundUsersAndGroups {
  const FoundUsersAndGroups({this.users = const [], this.groups = const []});

  final List<FoundUser> users;
  final List<FoundGroup> groups;
}
