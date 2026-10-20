import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Supplies UIKit's resolved viewport corners to Native components on iOS 26+.
///
/// Install once above the navigator. Framework-reported display corners take
/// precedence. Other hosts and older iOS versions retain their existing metrics.
class DDisplayCornerRadii extends StatefulWidget {
  const DDisplayCornerRadii({super.key, required this.child});
  final Widget child;
  @override
  State<DDisplayCornerRadii> createState() => _DDisplayCornerRadiiState();
}

class _DDisplayCornerRadiiState extends State<DDisplayCornerRadii> {
  static const _channel = MethodChannel('org.discourse.native/window_geometry');
  ({Size size, BorderRadius radii})? _geometry;
  int _generation = 0;
  late final bool _usesNative =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (!_usesNative) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'geometryChanged' && mounted) {
        _generation++;
        setState(() => _geometry = _decode(call.arguments));
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = _generation;
    try {
      final payload = await _channel.invokeMethod<Object?>('geometry');
      if (mounted && generation == _generation) {
        setState(() => _geometry = _decode(payload));
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  void dispose() {
    if (_usesNative) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final geometry = _geometry;
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    final useNative =
        media.displayCornerRadii == null &&
        geometry != null &&
        (size.width - geometry.size.width).abs() <= .01 &&
        (size.height - geometry.size.height).abs() <= .01;
    return MediaQuery(
      data: useNative ? media.applyDisplayCornerRadii(geometry.radii) : media,
      child: widget.child,
    );
  }
}

({Size size, BorderRadius radii})? _decode(Object? payload) {
  if (payload is! Map) return null;
  double? number(String key) {
    final value = payload[key];
    if (value is! num || !value.isFinite || value < 0) return null;
    return value.toDouble();
  }

  final width = number('width');
  final height = number('height');
  final topLeft = number('topLeft');
  final topRight = number('topRight');
  final bottomLeft = number('bottomLeft');
  final bottomRight = number('bottomRight');
  if (width == null ||
      width == 0 ||
      height == null ||
      height == 0 ||
      topLeft == null ||
      topRight == null ||
      bottomLeft == null ||
      bottomRight == null) {
    return null;
  }
  return (
    size: Size(width, height),
    radii: BorderRadius.only(
      topLeft: Radius.circular(topLeft),
      topRight: Radius.circular(topRight),
      bottomLeft: Radius.circular(bottomLeft),
      bottomRight: Radius.circular(bottomRight),
    ),
  );
}
