import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Wraps everything to the right of the rail.
///
/// The panel stops below the status bar and rounds the edge facing the rail, so
/// it reads as sitting *on* the backdrop rather than filling the window. The
/// backdrop showing through above it is the scaffold background.
///
/// Only the top-left corner is rounded. A divider-coloured outline keeps the
/// header and content inside one continuous frame, including where the bottom
/// and right edges meet the window.
class ShellPanel extends StatelessWidget {
  const ShellPanel({super.key, required this.child});

  static const double cornerRadius = 12;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(cornerRadius),
    );

    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: Theme.of(context).shell.divider),
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          // The inset above is the status bar clearance, so anything inside
          // must not apply it a second time.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ),
    );
  }
}
