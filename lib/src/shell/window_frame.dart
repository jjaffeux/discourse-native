import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The native window frame in screen points, including changes during a drag.
final class WindowFrame extends ValueNotifier<Rect?> {
  WindowFrame() : super(null) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    _channel.setMethodCallHandler(_handleCall);
    unawaited(_readInitialFrame());
  }

  static const _channel = MethodChannel('org.discourse.native/window');

  Future<void> _readInitialFrame() async {
    try {
      final frame = _decode(await _channel.invokeMethod('getWindowFrame'));
      if (!_disposed && value == null) value = frame;
    } on MissingPluginException {
      // Other desktop hosts do not provide the macOS window channel.
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'windowFrameChanged') return;
    final frame = _decode(call.arguments);
    if (!_disposed && frame != null) value = frame;
  }

  static Rect? _decode(Object? raw) {
    if (raw case {
      'x': final num x,
      'y': final num y,
      'width': final num width,
      'height': final num height,
    }) {
      return Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        width.toDouble(),
        height.toDouble(),
      );
    }
    return null;
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
