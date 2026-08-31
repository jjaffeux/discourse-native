import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class PlatformNotificationOpens {
  PlatformNotificationOpens({
    EventChannel? channel,
    TargetPlatform? platform,
    bool? isWeb,
  }) : _channel =
           channel ??
           const EventChannel('org.discourse.native/notification_opens'),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb;

  final EventChannel _channel;
  final TargetPlatform _platform;
  final bool _isWeb;
  Stream<String>? _urls;

  Stream<String> get urls {
    if (_isWeb ||
        (_platform != TargetPlatform.iOS &&
            _platform != TargetPlatform.macOS)) {
      return const Stream<String>.empty();
    }
    return _urls ??= _channel
        .receiveBroadcastStream()
        .where((event) => event is String && event.isNotEmpty)
        .cast<String>();
  }
}
