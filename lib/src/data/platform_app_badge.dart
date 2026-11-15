import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Draws a count on the app icon: the iOS badge, the macOS Dock tile, and on
/// Android the launcher's own count of this app's notifications.
abstract interface class AppBadge {
  Future<void> setCount(int count);
}

final class PlatformAppBadge implements AppBadge {
  PlatformAppBadge({MethodChannel? channel, TargetPlatform? platform})
    : _channel =
          channel ?? const MethodChannel('org.discourse.native/app_badge'),
      _platform = platform ?? defaultTargetPlatform;

  final MethodChannel _channel;
  final TargetPlatform _platform;

  @override
  Future<void> setCount(int count) async {
    if (kIsWeb) return;
    switch (_platform) {
      case TargetPlatform.iOS || TargetPlatform.macOS || TargetPlatform.android:
        break;
      case _:
        return;
    }
    try {
      await _channel.invokeMethod<void>('setBadgeCount', count);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
