import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Delivers the Discourse URL attached to an Apple notification after the user
/// opens it.
///
/// The native runners retain cold-start taps until this stream is listening.
/// Other platforms expose an empty stream, so notification navigation remains
/// an optional platform capability.
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
