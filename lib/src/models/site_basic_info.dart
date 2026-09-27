import 'package:flutter/foundation.dart';

/// What a forum's `/site/basic-info.json` says about it. Discourse serves that
/// route to every reader, including a signed-out one of a login-required
/// forum, so it is the one place a forum's name, icon and privacy can be read
/// before, and without, an account.
@immutable
final class SiteBasicInfo {
  const SiteBasicInfo({
    required this.title,
    this.description,
    this.iconUrl,
    this.loginRequired = false,
  });

  final String title;
  final String? description;

  /// Absolute, resolved against the forum's base address.
  final String? iconUrl;
  final bool loginRequired;
}
