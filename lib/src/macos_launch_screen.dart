import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Hands the macOS launch placeholder over only after Flutter has painted.
abstract final class MacOSLaunchScreen {
  static const _windowChannel = MethodChannel('org.discourse.native/window');

  static void dismissAfterFirstFlutterFrame() {
    if (defaultTargetPlatform != TargetPlatform.macOS) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_windowChannel.invokeMethod<void>('dismissLaunchScreen'));
    });
  }
}
