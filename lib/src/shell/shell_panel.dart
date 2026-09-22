import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/composer_placement.dart';
import '../theme/app_theme.dart';
import 'composer_presentation.dart';
import 'forum_theme_surfaces.dart';
import 'platform.dart';
import 'shell_metrics.dart';

class ShellPanel extends StatelessWidget {
  const ShellPanel({super.key, required this.child});

  static const double cornerRadius = DRadius.panel;

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
  const WorkspacePanel({
    super.key,
    required this.child,
    this.atRightEdge = true,
  });

  final Widget child;
  final bool atRightEdge;

  @override
  Widget build(BuildContext context) => context.isTouch
      ? child
      : DCard(
          spacing: 0,
          borderRadius: WorkspacePanelCorner.borderRadiusOf(
            context,
            atRightEdge: atRightEdge,
          ),
          backgroundColor: ForumWindowBackground.panelColor(context),
          child: Expanded(child: child),
        );
}

/// Split layouts pass the window corner only to the pane that still touches it.
class WorkspacePanelCorner extends InheritedWidget {
  const WorkspacePanelCorner({
    super.key,
    required this.radius,
    required super.child,
  });

  final double? radius;

  static double? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WorkspacePanelCorner>()
      ?.radius;

  static BorderRadius? borderRadiusOf(
    BuildContext context, {
    bool atRightEdge = true,
  }) {
    final radius = of(context);
    // Inner cards (including appearance previews) are inside an existing panel,
    // so they cannot share the physical window corner.
    if (radius == null ||
        !atRightEdge ||
        context.findAncestorWidgetOfExactType<DCard>() != null) {
      return null;
    }
    return BorderRadius.circular(
      DRadius.panel,
    ).copyWith(bottomRight: Radius.circular(radius));
  }

  @override
  bool updateShouldNotify(WorkspacePanelCorner oldWidget) =>
      radius != oldWidget.radius;
}

/// Desktop breathing room around the workspace; touch retains its shell frame.
class ShellWorkspace extends StatefulWidget {
  const ShellWorkspace({
    super.key,
    required this.child,
    this.atWindowEdge = true,
  });

  final Widget child;
  final bool atWindowEdge;

  @override
  State<ShellWorkspace> createState() => _ShellWorkspaceState();
}

class _ShellWorkspaceState extends State<ShellWorkspace>
    with WidgetsBindingObserver {
  static const _window = MethodChannel('org.discourse.native/window');
  // The titlebar-only macOS window uses a 16pt corner. The host supplies the
  // legacy/full-screen radius; subtract the workspace inset for concentric arcs.
  double _windowRadius = 16;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_readWindowRadius());
  }

  @override
  void didChangeMetrics() => unawaited(_readWindowRadius());

  Future<void> _readWindowRadius() async {
    if (kIsWeb || Theme.of(context).platform != TargetPlatform.macOS) return;
    final request = ++_request;
    try {
      final radius = await _window.invokeMethod<num>('getWindowCornerRadius');
      if (mounted &&
          request == _request &&
          radius != null &&
          radius.isFinite &&
          radius >= 0 &&
          radius != _windowRadius) {
        setState(() => _windowRadius = radius.toDouble());
      }
    } on MissingPluginException {
      // Standalone widget previews do not have the native window host.
    } on PlatformException {
      // Retain the last shape if the native window is temporarily unavailable.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => context.isTouch
      ? ShellPanel(child: widget.child)
      : WorkspacePanelCorner(
          radius:
              !kIsWeb &&
                  Theme.of(context).platform == TargetPlatform.macOS &&
                  widget.atWindowEdge &&
                  Directionality.of(context) == TextDirection.ltr
              ? math.max(0, _windowRadius - workspaceEdgeInset)
              : null,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              top: MediaQuery.paddingOf(context).top,
              end: workspaceEdgeInset,
              bottom: workspaceEdgeInset,
            ),
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),
        );
}
