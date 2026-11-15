import 'package:flutter/foundation.dart';

import 'json.dart';

/// One browser session signed in to the account, as core's
/// `UserAuthTokenSerializer` describes it. This app's own user API key is not
/// one of them.
///
/// The session's IP address is deliberately not read: nothing here shows it.
@immutable
final class UserAuthToken {
  const UserAuthToken({
    required this.id,
    this.browser = '',
    this.device = '',
    this.os = '',
    this.location = '',
    this.seenAt,
    this.isActive = false,
  });

  /// Null for a row without an id, which could not be named in a request.
  static UserAuthToken? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = jsonIntOrNull(value['id']);
    if (id == null) return null;
    return UserAuthToken(
      id: id,
      browser: jsonText(value['browser'])?.trim() ?? '',
      device: jsonText(value['device'])?.trim() ?? '',
      os: jsonText(value['os'])?.trim() ?? '',
      location: jsonText(value['location'])?.trim() ?? '',
      seenAt: jsonDate(value['seen_at']),
      isActive: value['is_active'] == true,
    );
  }

  final int id;

  /// Already worded by the site in the reader's locale, as are [device], [os]
  /// and [location].
  final String browser;
  final String device;
  final String os;
  final String location;
  final DateTime? seenAt;

  /// The session that made the request. Core refuses to revoke it by id, and
  /// it is never true for a request signed with a user API key.
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      other is UserAuthToken &&
      other.id == id &&
      other.browser == browser &&
      other.device == device &&
      other.os == os &&
      other.location == location &&
      other.seenAt == seenAt &&
      other.isActive == isActive;

  @override
  int get hashCode =>
      Object.hash(id, browser, device, os, location, seenAt, isActive);
}
