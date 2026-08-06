import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The strip across the very top of the window, spanning every column.
///
/// The macOS window has no title bar of its own (see MainFlutterWindow.swift),
/// so this stands in for it: it keeps the traffic lights clear of the rail and
/// gives us a full-width band to put window-level chrome in later. Nothing
/// lives in it yet — for now it only reserves the space.
///
/// Only desktop platforms that hide their native title bar get the strip; on
/// phones the status bar already plays this role, so the height is zero there
/// and the layout is unchanged.
class ShellTitleBar extends StatelessWidget {
  const ShellTitleBar({super.key});

  /// Enough room for the traffic lights plus a little breathing space.
  static const double _height = 38;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static double height(BuildContext context) => isSupported ? _height : 0;

  @override
  Widget build(BuildContext context) {
    if (!isSupported) return const SizedBox.shrink();

    // Same color as the backdrop the rail sits on, so the strip reads as part
    // of the window frame rather than as a row of its own.
    return SizedBox(
      height: _height,
      child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
    );
  }
}
