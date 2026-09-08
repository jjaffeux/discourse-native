import 'package:flutter/foundation.dart';

import 'discourse_instance.dart';
import 'json.dart';

@immutable
final class BadgeRoute {
  const BadgeRoute.directory() : badgeId = null, slug = null, username = null;

  factory BadgeRoute.detail(int badgeId, {String? slug, String? username}) {
    if (badgeId <= 0 || !_validSegment(slug) || !_validSegment(username)) {
      throw ArgumentError('Invalid badge route');
    }
    return BadgeRoute._(badgeId, slug, username);
  }

  const BadgeRoute._(this.badgeId, this.slug, this.username);

  final int? badgeId;
  final String? slug;
  final String? username;

  bool get isDirectory => badgeId == null;

  String get id => isDirectory
      ? 'badges'
      : 'badge-$badgeId${username == null ? '' : '-user-${Uri.encodeComponent(username!)}'}';

  String get path => Uri(
    pathSegments: ['', 'badges', if (badgeId != null) '$badgeId', ?slug],
    queryParameters: username == null ? null : {'username': username!},
  ).toString();

  Map<String, Object?> toJson() => {
    if (badgeId != null) 'badge_id': badgeId,
    if (slug != null) 'slug': slug,
    if (username != null) 'username': username,
  };

  factory BadgeRoute.fromJson(Map<String, dynamic> json) {
    final id = json['badge_id'];
    final slug = json['slug'];
    final username = json['username'];
    if (id == null && slug == null && username == null) {
      return const BadgeRoute.directory();
    }
    if (id is! int ||
        (slug != null && slug is! String) ||
        (username != null && username is! String)) {
      throw const FormatException('Invalid badge route');
    }
    try {
      return BadgeRoute.detail(
        id,
        slug: slug as String?,
        username: username as String?,
      );
    } on ArgumentError {
      throw const FormatException('Invalid badge route');
    }
  }

  static BadgeRoute? parse(String url, {required String siteUrl}) {
    if (url.isEmpty || url.length > 2048) return null;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        (uri.hasScheme && uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    final decoded = DiscourseInstance.pathSegmentsWithin(siteUrl, uri);
    if (decoded == null) return null;
    final segments = [...decoded];
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    if (segments.isEmpty || segments.first != 'badges') return null;
    if (segments.length == 1) return const BadgeRoute.directory();
    if (segments.length > 3) return null;
    final id = jsonIntOrNull(segments[1]);
    if (id == null || id <= 0) return null;
    try {
      return BadgeRoute.detail(
        id,
        slug: segments.length == 3 ? segments[2] : null,
        username: jsonText(uri.queryParameters['username']),
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static bool _validSegment(String? value) =>
      value == null ||
      (value.isNotEmpty &&
          value.length <= 255 &&
          value.trim() == value &&
          !RegExp(r'[/\\\x00-\x1f]').hasMatch(value));

  @override
  bool operator ==(Object other) =>
      other is BadgeRoute &&
      other.badgeId == badgeId &&
      other.username == username;

  @override
  int get hashCode => Object.hash(badgeId, username);
}
