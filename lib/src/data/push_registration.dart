import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The address a Discourse site should hand to the shared push service.
class PushRegistration {
  const PushRegistration({required this.clientId, required this.pushUrl});

  /// APNs or FCM device token. Discourse forwards it as `client_id`.
  final String clientId;

  /// Provider endpoint Discourse calls when it has a notification for us.
  final String pushUrl;
}

abstract interface class PushRegistrationProvider {
  Future<PushRegistration?> registration();
}

/// Retrieves the current platform token without making push a sign-in
/// requirement.
///
/// iOS and macOS use APNs. A missing bridge, denied permission, or failed APNs
/// registration returns no registration, so the account can still connect
/// with its ordinary per-install client id.
final class PlatformPushRegistrationProvider
    implements PushRegistrationProvider {
  PlatformPushRegistrationProvider({
    MethodChannel? channel,
    TargetPlatform? platform,
  }) : _channel =
           channel ??
           const MethodChannel('org.discourse.native/push_notifications'),
       _platform = platform ?? defaultTargetPlatform;

  static const macosPushUrl =
      'https://api.discourse.org/api/publish_native_macos';
  static const iosPushUrl = 'https://api.discourse.org/api/publish_native_ios';

  final MethodChannel _channel;
  final TargetPlatform _platform;

  @override
  Future<PushRegistration?> registration() async {
    final pushUrl = switch (_platform) {
      TargetPlatform.iOS => iosPushUrl,
      TargetPlatform.macOS => macosPushUrl,
      _ => null,
    };
    if (pushUrl == null) return null;

    try {
      final token = await _channel.invokeMethod<String>('registrationToken');
      if (token == null || token.isEmpty) return null;
      return PushRegistration(clientId: token, pushUrl: pushUrl);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
