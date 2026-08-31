import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
