import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/composer_placement.dart';
import '../theme/app_theme.dart';
import 'composer_presentation.dart';
import 'platform.dart';
import 'shell_metrics.dart';

class ShellPanel extends StatelessWidget {
  const ShellPanel({super.key, required this.child});

  static const double cornerRadius = 12;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(cornerRadius),
    );
    final composerPlacement = ComposerDock.workspacePlacementOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final side = BorderSide(color: Theme.of(context).shell.divider);

    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          // The rail precedes this panel. Only its outer side or bottom can
          // meet the app-level composer; the resize handle paints that seam.
          border: Border(
            top: side,
            left: rtl && composerPlacement == ComposerPlacement.left
                ? BorderSide.none
                : side,
            right: !rtl && composerPlacement == ComposerPlacement.right
                ? BorderSide.none
                : side,
            bottom: composerPlacement == ComposerPlacement.bottom
                ? BorderSide.none
                : side,
          ),
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

/// A bounded desktop workspace surface, styled and clipped by the Native kit.
class WorkspacePanel extends StatelessWidget {
  const WorkspacePanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => context.isTouch
      ? child
      : DCard(spacing: 0, child: Expanded(child: child));
}

/// Desktop breathing room around the workspace; touch retains its shell frame.
class ShellWorkspace extends StatelessWidget {
  const ShellWorkspace({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => context.isTouch
      ? ShellPanel(child: child)
      : Padding(
          padding: EdgeInsetsDirectional.only(
            top: MediaQuery.paddingOf(context).top,
            end: workspaceEdgeInset,
            bottom: workspaceEdgeInset,
          ),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        );
}
