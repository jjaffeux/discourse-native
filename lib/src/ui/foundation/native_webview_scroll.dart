import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Routes the window's native WebView wheel events to their Flutter reader.
///
/// The channel retains its original YouTube name for native compatibility.
/// Each surface checks its visible bounds and hit path before claiming a delta.
final class NativeWebViewScrollBridge {
  static const _channel = MethodChannel('org.discourse.native/youtube_scroll');
  static final Map<Object, bool Function(Offset, double)> _targets = {};
  static bool _listening = false;

  static void register(Object owner, bool Function(Offset, double) target) {
    if (!_listening) {
      _channel.setMethodCallHandler(_handleMethodCall);
      _listening = true;
    }
    _targets[owner] = target;
  }

  static void unregister(Object owner) => _targets.remove(owner);

  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'scroll' || call.arguments is! Map) return;
    final arguments = call.arguments as Map;
    final x = arguments['x'];
    final y = arguments['y'];
    final deltaY = arguments['deltaY'];
    if (x is! num || y is! num || deltaY is! num) return;
    final position = Offset(x.toDouble(), y.toDouble());
    final delta = deltaY.toDouble();
    if (!position.dx.isFinite || !position.dy.isFinite || !delta.isFinite) {
      return;
    }

    for (final target in _targets.values.toList().reversed) {
      if (target(position, delta)) return;
    }

    // A covering dialog or panel, rather than an embed, may own the hit.
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    GestureBinding.instance.handlePointerEvent(
      PointerScrollEvent(
        viewId: view.viewId,
        kind: PointerDeviceKind.mouse,
        position: position,
        scrollDelta: Offset(0, delta),
      ),
    );
  }
}
