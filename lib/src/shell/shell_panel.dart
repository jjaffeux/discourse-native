import 'package:flutter/material.dart';

/// Wraps everything to the right of the rail.
///
/// The panel stops below the status bar and rounds the edge facing the rail, so
/// it reads as sitting *on* the backdrop rather than filling the window. The
/// backdrop showing through above it is the scaffold background.
///
/// Only the top-left corner is rounded. The bottom edge meets the window edge,
/// and the right edge meets the window's right edge.
class ShellPanel extends StatelessWidget {
  const ShellPanel({super.key, required this.child});

  static const double cornerRadius = 12;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(cornerRadius),
        ),
        // The inset above is the status bar clearance, so anything inside must
        // not apply it a second time.
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: child,
        ),
      ),
    );
  }
}
