import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/discourse_typography.dart';
import 'app_settings_controller.dart';

/// Applies the app's text-size preference without replacing the platform's
/// accessibility text scaler.
class AppTextScaleRegion extends StatefulWidget {
  const AppTextScaleRegion({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppSettingsController controller;
  final Widget child;

  @override
  State<AppTextScaleRegion> createState() => _AppTextScaleRegionState();
}

class _AppTextScaleRegionState extends State<AppTextScaleRegion> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final keyboard = HardwareKeyboard.instance;
    final platform = defaultTargetPlatform;
    final apple =
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
    final primaryPressed = apple
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final secondaryPressed = apple
        ? keyboard.isControlPressed
        : keyboard.isMetaPressed;
    if (!primaryPressed || secondaryPressed || keyboard.isAltPressed) {
      return false;
    }

    switch (event.character) {
      case '+' || '=':
        unawaited(widget.controller.increaseTextScale());
        return true;
      case '-':
        unawaited(widget.controller.decreaseTextScale());
        return true;
      case '0':
        unawaited(widget.controller.resetTextScale());
        return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.add ||
        event.logicalKey == LogicalKeyboardKey.numpadAdd) {
      unawaited(widget.controller.increaseTextScale());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
      unawaited(widget.controller.decreaseTextScale());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.numpad0) {
      unawaited(widget.controller.resetTextScale());
      return true;
    }

    if (event.character?.isNotEmpty == true) return false;
    if (event.logicalKey == LogicalKeyboardKey.equal) {
      unawaited(widget.controller.increaseTextScale());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.minus) {
      unawaited(widget.controller.decreaseTextScale());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit0) {
      unawaited(widget.controller.resetTextScale());
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, child) {
      final mediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: AppTextScaler(
            platformScaler: mediaQuery.textScaler,
            appScale: widget.controller.textScaleFactor,
          ),
        ),
        child: child!,
      );
    },
    child: widget.child,
  );
}

@immutable
final class AppTextScaler extends TextScaler {
  const AppTextScaler({required this.platformScaler, required this.appScale})
    : assert(appScale > 0);

  final TextScaler platformScaler;
  final double appScale;

  @override
  double scale(double fontSize) => platformScaler.scale(fontSize) * appScale;

  @override
  double get textScaleFactor {
    // flutter_widget_from_html_core still reads this compatibility value when
    // laying out cooked posts. Anchor its linear estimate to the app's 16px
    // body text until it consumes TextScaler directly.
    return scale(DiscourseTypography.base) / DiscourseTypography.base;
  }

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.platformScaler == platformScaler &&
      other.appScale == appScale;

  @override
  int get hashCode => Object.hash(platformScaler, appScale);
}
