import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The `discourse://open` requests the platform handed this app, unparsed.
///
/// The runner holds a request that launched the app until `listen` tells it
/// Dart is ready, then calls `open` for that one and each later one. A runner
/// without the forwarder is a platform with no requests, not an error.
final class PlatformLinkOpens {
  PlatformLinkOpens({
    MethodChannel? channel,
    TargetPlatform? platform,
    bool? isWeb,
  }) : _channel =
           channel ?? const MethodChannel('org.discourse.native/link_opens'),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb;

  final MethodChannel _channel;
  final TargetPlatform _platform;
  final bool _isWeb;
  late final StreamController<String> _requests =
      StreamController<String>.broadcast(
        onListen: () {
          _channel.setMethodCallHandler((call) async {
            final request = call.arguments;
            if (call.method == 'open' &&
                request is String &&
                request.isNotEmpty) {
              _requests.add(request);
            }
          });
          unawaited(_listen());
        },
        onCancel: () => _channel.setMethodCallHandler(null),
      );

  Stream<String> get requests {
    if (_isWeb ||
        (_platform != TargetPlatform.iOS &&
            _platform != TargetPlatform.macOS &&
            _platform != TargetPlatform.android &&
            _platform != TargetPlatform.linux)) {
      return const Stream<String>.empty();
    }
    return _requests.stream;
  }

  void dispose() {
    unawaited(_requests.close());
  }

  Future<void> _listen() async {
    try {
      await _channel.invokeMethod<void>('listen');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
