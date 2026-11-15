import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import 'push_registration.dart';
import 'site_preference_keys.dart';

/// Names a device token without storing it: enough to tell two tokens apart,
/// useless for addressing a push.
String pushTokenFingerprint(String token) {
  final digest = SHA256Digest().process(Uint8List.fromList(utf8.encode(token)));
  return [
    for (final byte in digest.take(16)) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// What a forum was told when an account last authorized on this device.
final class PushRegistrationRecord {
  const PushRegistrationRecord({
    required this.fingerprint,
    required this.accepted,
  });

  PushRegistrationRecord.authorized(PushAuthorization authorization)
    : fingerprint = switch (authorization.registration) {
        final registration? => pushTokenFingerprint(registration.clientId),
        null => null,
      },
      accepted = authorization.accepted;

  /// Null when the platform offered no token at that authorization.
  final String? fingerprint;

  /// False when the forum declined the push URL; a new token changes nothing.
  final bool accepted;

  static PushRegistrationRecord? decode(String? stored) {
    if (stored == null || stored.length < 2 || stored[1] != ':') return null;
    final accepted = switch (stored[0]) {
      '1' => true,
      '0' => false,
      _ => null,
    };
    if (accepted == null) return null;
    final fingerprint = stored.substring(2);
    return PushRegistrationRecord(
      fingerprint: fingerprint.isEmpty ? null : fingerprint,
      accepted: accepted,
    );
  }

  String encode() => '${accepted ? 1 : 0}:${fingerprint ?? ''}';
}

enum PushRegistrationDrift {
  none,

  /// The forum still pushes to a token this device no longer holds.
  rotated,

  /// The account authorized without a token and the device has one now.
  newlyAvailable,
}

/// Compares what the forum was told with the token held now. Without a current
/// token there is nothing a new authorization could register.
PushRegistrationDrift pushRegistrationDrift(
  PushRegistrationRecord recorded,
  String? currentFingerprint,
) {
  if (currentFingerprint == null) return PushRegistrationDrift.none;
  final registered = recorded.fingerprint;
  if (registered == null) return PushRegistrationDrift.newlyAvailable;
  if (registered == currentFingerprint || !recorded.accepted) {
    return PushRegistrationDrift.none;
  }
  return PushRegistrationDrift.rotated;
}

class PushRegistrationLedger {
  const PushRegistrationLedger();

  static const _records = OwnedSitePreferences(
    id: 'push.registration',
    scope: SitePreferenceScope.account,
    value: SitePreferenceValue.string,
  );
  static const _dismissals = OwnedSitePreferences(
    id: 'push.reauthorization-dismissed',
    scope: SitePreferenceScope.account,
    value: SitePreferenceValue.string,
  );

  static SitePreferenceIdentity _account(String siteUrl, String username) =>
      SitePreferenceIdentity.account(siteUrl, username.toLowerCase());

  Future<PushRegistrationRecord?> read(String siteUrl, String username) async =>
      PushRegistrationRecord.decode(
        await _records.read(_account(siteUrl, username)),
      );

  Future<void> write(
    String siteUrl,
    String username,
    PushRegistrationRecord record,
  ) => _records.write(_account(siteUrl, username), record.encode());

  /// The current-token fingerprint the user last declined to act on.
  Future<String?> dismissed(String siteUrl, String username) =>
      _dismissals.read(_account(siteUrl, username));

  Future<void> dismiss(String siteUrl, String username, String fingerprint) =>
      _dismissals.write(_account(siteUrl, username), fingerprint);
}
