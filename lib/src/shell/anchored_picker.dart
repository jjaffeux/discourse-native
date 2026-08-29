import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'anchored_layout.dart';
import 'platform.dart';
import 'shell_sheet.dart';

/// Opens picker content in a compact popover for pointers and a sheet for
/// touch input.
///
/// Sidebar property pickers share this route so switching between category
/// and tag editing does not also switch surface geometry or animation.
Future<T?> showAnchoredPicker<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required String title,
  required String barrierLabel,
  required Key popoverKey,
  required WidgetBuilder builder,
}) {
  if (context.isTouch) {
    return showShellSheet<T>(
      context: context,
      title: title,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      builder: builder,
    );
  }

  final navigator = Navigator.of(context);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  final anchor = anchorRect(
    anchor: anchorContext.findRenderObject() as RenderBox?,
    overlay: overlay,
  );
  final media = MediaQuery.of(context);
  final alignment = anchor == null
      ? Alignment.center
      : Alignment(
          anchor.center.dx > media.size.width / 2 ? 1 : -1,
          anchor.center.dy > media.size.height / 2 ? 1 : -1,
        );
  final duration = media.disableAnimations
      ? Duration.zero
      : discourseMenuOpenDuration;

  return navigator.push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      reverseTransitionDuration: media.disableAnimations
          ? Duration.zero
          : discourseMenuCloseDuration,
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          CustomSingleChildLayout(
            delegate: AnchoredLayout(
              anchor: anchor,
              maxWidth: _AnchoredPickerSurface.width,
              gap: 4,
              margin: 10,
            ),
            child: _AnchoredPickerTransition(
              animation: animation,
              alignment: alignment,
              child: _AnchoredPickerSurface(
                key: popoverKey,
                child: builder(routeContext),
              ),
            ),
          ),
    ),
  );
}

class _AnchoredPickerTransition extends StatelessWidget {
  const _AnchoredPickerTransition({
    required this.animation,
    required this.alignment,
    required this.child,
  });

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        alignment: alignment,
        child: child,
      ),
    );
  }
}

class _AnchoredPickerSurface extends StatelessWidget {
  const _AnchoredPickerSurface({super.key, required this.child});

  static const double width = 360;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const radius = BorderRadius.all(Radius.circular(12));
    return Material(
      color: theme.shell.floating,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          border: Border.all(color: theme.shell.divider),
          borderRadius: radius,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: child,
        ),
      ),
    );
  }
}
