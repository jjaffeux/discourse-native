/// Ignoring a person, as the web client's ignore dialog does: one request per
/// person on `/u/{username}/notification_level`, where the username is the
/// person being ignored.
abstract interface class UserIgnoresApi {
  /// Ignores [username] until [until]. Core also lifts a mute of the same
  /// person, since the two levels exclude each other.
  Future<void> ignoreUser({
    required String siteUrl,
    required String apiKey,
    required String username,
    required DateTime until,
    String? clientId,
  });

  /// Returns [username] to the normal level, which lifts an ignore and a mute.
  Future<void> stopIgnoringUser({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });
}
