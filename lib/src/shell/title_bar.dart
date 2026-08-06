import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'user_menu_button.dart';

/// The strip across the very top of the window, spanning every column.
///
/// The macOS window has no title bar of its own (see MainFlutterWindow.swift),
/// so this stands in for it: it keeps the traffic lights clear of the rail and
/// gives us a full-width band for window-level chrome. The account avatar lives
/// at its right end, which is the top right corner of the window itself rather
/// than of any one column.
///
/// Only desktop platforms that hide their native title bar get the strip; on
/// phones the status bar already plays this role, so the height is zero there
/// and the columns carry the avatar in their own headers instead.
class ShellTitleBar extends StatelessWidget {
  const ShellTitleBar({super.key});

  /// Enough room for the traffic lights plus a little breathing space.
  static const double _height = 38;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static double height(BuildContext context) => isSupported ? _height : 0;

  /// Where the account avatar goes when there is no strip to hold it.
  static bool get columnsCarryUserMenu => !isSupported;

  @override
  Widget build(BuildContext context) {
    if (!isSupported) return const SizedBox.shrink();

    // Same color as the backdrop the rail sits on, so the strip reads as part
    // of the window frame rather than as a row of its own.
    final surface = Theme.of(context).scaffoldBackgroundColor;

    return SizedBox(
      height: _height,
      child: ColoredBox(
        color: surface,
        child: Row(
          children: [
            // The traffic lights own the left end.
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: UserMenuButton(size: 26, ringColor: surface),
            ),
          ],
        ),
      ),
    );
  }
}
