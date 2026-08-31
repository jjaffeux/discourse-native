import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PushRegistration {
  const PushRegistration({required this.clientId, required this.pushUrl});

  final String clientId;

  final String pushUrl;
}

abstract interface class PushRegistrationProvider {
  Future<PushRegistration?> registration();
}

final class PlatformPushRegistrationProvider
    implements PushRegistrationProvider {
  PlatformPushRegistrationProvider({
    MethodChannel? channel,
    TargetPlatform? platform,
    this.registrationTimeout = const Duration(seconds: 15),
  }) : _channel =
           channel ??
           const MethodChannel('org.discourse.native/push_notifications'),
       _platform = platform ?? defaultTargetPlatform;

  static const macosPushUrl =
      'https://api.discourse.org/api/publish_native_macos';
  static const iosPushUrl = 'https://api.discourse.org/api/publish_native_ios';

  final MethodChannel _channel;
  final TargetPlatform _platform;
  final Duration registrationTimeout;

  @override
  Future<PushRegistration?> registration() async {
    final pushUrl = switch (_platform) {
      TargetPlatform.iOS => iosPushUrl,
      TargetPlatform.macOS => macosPushUrl,
      _ => null,
    };
    if (pushUrl == null) return null;

    try {
      final token = await _channel
          .invokeMethod<String>('registrationToken')
          .timeout(registrationTimeout);
      if (token == null || token.isEmpty) return null;
      return PushRegistration(clientId: token, pushUrl: pushUrl);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
