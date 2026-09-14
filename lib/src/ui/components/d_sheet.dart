import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_dialog.dart';

/// The four documented physical edges plus direction-aware conveniences.
enum DSheetSide { top, right, bottom, left, start, end }

extension on DSheetSide {
  DSheetSide resolve(TextDirection direction) => switch (this) {
    DSheetSide.start =>
      direction == TextDirection.ltr ? DSheetSide.left : DSheetSide.right,
    DSheetSide.end =>
      direction == TextDirection.ltr ? DSheetSide.right : DSheetSide.left,
    _ => this,
  };

  bool get isHorizontal => this == DSheetSide.left || this == DSheetSide.right;
}

typedef DSheetController<T> = DDialogController<T>;

typedef DSheetChangeDetails<T> = DDialogChangeDetails<T>;
typedef DSheetChangeReason = DDialogChangeReason;
typedef DSheetTriggerBuilder =
    Widget Function(BuildContext context, VoidCallback open);

class DSheetTrigger extends StatelessWidget {
  const DSheetTrigger({super.key, required this.builder});

  final DSheetTriggerBuilder builder;

  @override
  Widget build(BuildContext context) => DDialogTrigger(builder: builder);
}

/// Declarative Sheet root using Dialog's route and controller ownership.
class DSheet<T> extends StatelessWidget {
  const DSheet({
    super.key,
    required this.trigger,
    required this.content,
    this.controller,
    this.open,
    this.initiallyOpen = false,
    this.onOpenChanged,
    this.useRootNavigator = false,
    this.dismissOnBarrier = true,
    this.dismissOnEscape = true,
    this.barrierLabel = 'Dismiss sheet',
    this.routeSettings,
    this.initialFocusNode,
    this.finalFocusNode,
  }) : assert(open == null || !initiallyOpen);

  final DSheetTrigger trigger;
  final DSheetContent content;
  final DSheetController<T>? controller;
  final bool? open;
  final bool initiallyOpen;
  final ValueChanged<DSheetChangeDetails<T>>? onOpenChanged;
  final bool useRootNavigator;
  final bool dismissOnBarrier;
  final bool dismissOnEscape;
  final String barrierLabel;
  final RouteSettings? routeSettings;
  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;

  @override
  Widget build(BuildContext context) => DDialog<T>(
    controller: controller,
    open: open,
    initiallyOpen: initiallyOpen,
    onOpenChanged: onOpenChanged,
    useRootNavigator: useRootNavigator,
    dismissOnBarrier: dismissOnBarrier,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    routeSettings: routeSettings,
    initialFocusNode: initialFocusNode,
    finalFocusNode: finalFocusNode,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    presentationBuilder: (context, presentation) => _sheetPresentation(
      context,
      presentation,
      content.side,
      content.sidePanelMaxWidth,
      content.sidePanelWidth,
      content.inset,
      content.animateSize,
    ),
    trigger: DDialogTrigger(builder: trigger.builder),
    content: content,
  );
}

class _DSheetSideScope extends InheritedWidget {
  const _DSheetSideScope({
    required this.side,
    required this.inset,
    required super.child,
  });

  final DSheetSide side;
  final bool inset;

  static DSheetSide? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DSheetSideScope>()?.side;

  static bool? insetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DSheetSideScope>()?.inset;

  @override
  bool updateShouldNotify(_DSheetSideScope oldWidget) =>
      side != oldWidget.side || inset != oldWidget.inset;
}

Widget _sheetPresentation(
  BuildContext context,
  DDialogPresentation presentation,
  DSheetSide requestedSide,
  double maxWidth,
  double? width,
  bool inset,
  bool animateSize,
) {
  final media = MediaQuery.of(context);
  final side = requestedSide.resolve(Directionality.of(context));
  final popupCurve = CurvedAnimation(
    parent: presentation.animation,
    curve: Curves.easeInOut,
    reverseCurve: Curves.easeInOut,
  );
  final backdropCurve = CurvedAnimation(
    parent: presentation.animation,
    curve: const Interval(0, .75, curve: Curves.easeInOut),
    reverseCurve: const Interval(.25, 1, curve: Curves.easeInOut),
  );
  Widget backdrop = presentation.buildBackdrop();
  if (!media.disableAnimations) {
    backdrop = FadeTransition(opacity: backdropCurve, child: backdrop);
  }

  final beginOffset = switch (side) {
    DSheetSide.top => const Offset(0, -40),
    DSheetSide.right => const Offset(40, 0),
    DSheetSide.bottom => const Offset(0, 40),
    DSheetSide.left => const Offset(-40, 0),
    _ => throw StateError('Sheet side was not resolved.'),
  };
  Widget popup = _DSheetSideScope(
    side: side,
    inset: inset,
    child: presentation.content,
  );
  if (!media.disableAnimations) {
    popup = FadeTransition(
      opacity: popupCurve,
      child: AnimatedBuilder(
        animation: popupCurve,
        child: popup,
        builder: (context, child) => Transform.translate(
          offset: Offset.lerp(beginOffset, Offset.zero, popupCurve.value)!,
          child: child,
        ),
      ),
    );
  }

  return LayoutBuilder(
    builder: (context, bounds) {
      final margin = inset ? DSpacing.md : 0.0;
      final availableWidth = (bounds.maxWidth - margin * 2).clamp(
        0.0,
        double.infinity,
      );
      final panelWidth = width == null
          ? availableWidth < 640
                ? availableWidth * .75
                : (availableWidth * .75).clamp(0, maxWidth).toDouble()
          : width.clamp(0, maxWidth).clamp(0, availableWidth).toDouble();
      final horizontal = side.isHorizontal;
      final positioned = AnimatedPositioned(
        duration: animateSize
            ? DMotion.duration(context, DMotion.change)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        left: side == DSheetSide.right ? null : margin,
        right: side == DSheetSide.left ? null : margin,
        top: side == DSheetSide.bottom ? null : margin,
        bottom: side == DSheetSide.top ? null : margin,
        width: horizontal ? panelWidth : null,
        child: popup,
      );
      return Stack(
        children: [
          Positioned.fill(child: backdrop),
          positioned,
        ],
      );
    },
  );
}

/// The base-nova fixed-edge sheet surface.
class DSheetContent extends StatelessWidget {
  const DSheetContent({
    super.key,
    required this.children,
    this.side = DSheetSide.right,
    this.showCloseButton = true,
    this.closeButton,
    this.closeSemanticLabel = 'Close',
    this.semanticLabel,
    this.sidePanelMaxWidth = 384,
    this.sidePanelWidth,
    this.inset = false,
    this.animateSize = false,
    this.scrollWholeSheet,
    this.topBottomMaxHeightFactor,
  }) : assert(sidePanelMaxWidth > 0),
       assert(sidePanelWidth == null || sidePanelWidth > 0),
       assert(
         topBottomMaxHeightFactor == null ||
             (topBottomMaxHeightFactor > 0 && topBottomMaxHeightFactor <= 1),
       );

  final List<Widget> children;
  final DSheetSide side;
  final bool showCloseButton;
  final Widget? closeButton;
  final String closeSemanticLabel;
  final String? semanticLabel;
  final double sidePanelMaxWidth;

  /// An exact side-panel width, clamped to [sidePanelMaxWidth] and the viewport.
  ///
  /// Null preserves Sheet's responsive 75% width and 384px desktop cap.
  final double? sidePanelWidth;

  /// Floats the surface inside the viewport with shared spacing and rounded
  /// corners. The default retains the reference's fixed-edge presentation.
  final bool inset;

  /// Animates changes to the sheet's bounds without replacing its contents.
  /// Reduced-motion preferences always make these changes immediate.
  final bool animateSize;

  /// Overrides automatic whole-surface scrolling at large text sizes.
  ///
  /// Null preserves the default. Set false only when a composed child owns a
  /// bounded scroll region while its surrounding header and footer stay fixed.
  final bool? scrollWholeSheet;

  /// Optional cap used by long top and bottom compositions.
  final double? topBottomMaxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final inset = _DSheetSideScope.insetOf(context) ?? this.inset;
    final resolved =
        _DSheetSideScope.maybeOf(context) ??
        side.resolve(Directionality.of(context));
    final fillsHeight = resolved.isHorizontal;
    final hasBody = children.any((child) => child is DSheetBody);
    final scrollWholeSheet =
        this.scrollWholeSheet ??
        ((fillsHeight || topBottomMaxHeightFactor != null) &&
            (MediaQuery.textScalerOf(context).scale(1) > 1.5 ||
                (topBottomMaxHeightFactor != null && !hasBody)));
    final parts = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      final child = children[index];
      if (index > 0) parts.add(const SizedBox(height: DSpacing.lg));
      if (child is DSheetBody && fillsHeight && !scrollWholeSheet) {
        parts.add(Expanded(child: child));
      } else if (child is DSheetBody &&
          topBottomMaxHeightFactor != null &&
          !scrollWholeSheet) {
        parts.add(Flexible(child: child));
      } else if (fillsHeight && child is DSheetFooter) {
        if (!hasBody && !scrollWholeSheet) parts.add(const Spacer());
        parts.add(child);
      } else {
        parts.add(child);
      }
    }

    final edgeBorder = BorderSide(color: tokens.border);
    final border = inset
        ? Border.all(color: tokens.border)
        : switch (resolved) {
            DSheetSide.top => Border(bottom: edgeBorder),
            DSheetSide.right => Border(left: edgeBorder),
            DSheetSide.bottom => Border(top: edgeBorder),
            DSheetSide.left => Border(right: edgeBorder),
            _ => throw StateError('Sheet side was not resolved.'),
          };
    final radius = inset
        ? BorderRadius.circular(tokens.radius * 1.4)
        : BorderRadius.zero;
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .1),
            blurRadius: 15,
            offset: const Offset(0, 10),
            spreadRadius: -3,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .1),
            blurRadius: 6,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: border, borderRadius: radius),
        child: Material(
          animationDuration: Duration.zero,
          borderRadius: radius,
          clipBehavior: inset ? Clip.antiAlias : Clip.none,
          color: tokens.surface,
          textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: DiscourseTypography.sm,
            height: 20 / 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: tokens.foreground,
          ),
          child: SafeArea(
            minimum: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Stack(
              children: [
                if (scrollWholeSheet)
                  SingleChildScrollView(
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: parts,
                    ),
                  )
                else
                  Column(
                    mainAxisSize: fillsHeight
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: parts,
                  ),
                if (showCloseButton)
                  Positioned(
                    top: DSpacing.md,
                    right: DSpacing.md,
                    child:
                        closeButton ??
                        DSheetClose<void>(
                          builder: (context, close) => DButton.iconOnly(
                            onPressed: close,
                            size: DButtonSize.small,
                            variant: DButtonVariant.ghost,
                            icon: const _DSheetCloseIcon(),
                            tooltip: closeSemanticLabel,
                            semanticLabel: closeSemanticLabel,
                          ),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final maxHeightFactor = topBottomMaxHeightFactor;
    if (!fillsHeight && maxHeightFactor != null) {
      surface = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
        ),
        child: surface,
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      scopesRoute: true,
      label: semanticLabel,
      child: surface,
    );
  }
}

class DSheetHeader extends StatelessWidget {
  const DSheetHeader({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(DSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 2),
          children[index],
        ],
      ],
    ),
  );
}

class DSheetTitle extends StatelessWidget {
  const DSheetTitle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      header: true,
      namesRoute: true,
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
          fontSize: DiscourseTypography.base,
          height: 24 / 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: tokens.foreground,
        ),
        child: child,
      ),
    );
  }
}

class DSheetDescription extends StatelessWidget {
  const DSheetDescription({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: DTokens.of(context).mutedForeground,
    ),
    child: child,
  );
}

/// Scrollable body with the reference's 16px horizontal inset.
class DSheetBody extends StatelessWidget {
  const DSheetBody({
    super.key,
    required this.child,
    this.controller,
    this.padding = const EdgeInsets.symmetric(horizontal: DSpacing.lg),
  });

  final Widget child;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    primary: false,
    padding: padding,
    child: child,
  );
}

class DSheetFooter extends StatelessWidget {
  const DSheetFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(DSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: DSpacing.sm),
          children[index],
        ],
      ],
    ),
  );
}

typedef DSheetCloseBuilder =
    Widget Function(BuildContext context, VoidCallback close);

class DSheetClose<T> extends StatelessWidget {
  const DSheetClose({super.key, required this.builder, this.result});

  final DSheetCloseBuilder builder;
  final T? result;

  @override
  Widget build(BuildContext context) =>
      DDialogClose<T>(result: result, builder: builder);
}

class _DSheetCloseIcon extends StatelessWidget {
  const _DSheetCloseIcon();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CustomPaint(
      painter: _DSheetCloseIconPainter(
        IconTheme.of(context).color ?? DTokens.of(context).foreground,
      ),
    ),
  );
}

class _DSheetCloseIconPainter extends CustomPainter {
  const _DSheetCloseIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4 / 3
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(const Offset(4, 4), const Offset(12, 12), paint)
      ..drawLine(const Offset(12, 4), const Offset(4, 12), paint);
  }

  @override
  bool shouldRepaint(_DSheetCloseIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

typedef DSheetContentBuilder<T> =
    DSheetContent Function(
      BuildContext context,
      DSheetController<T> controller,
    );

/// Opens a route-owned Sheet and returns its typed result.
Future<T?> showDSheet<T>({
  required BuildContext context,
  required DSheetContentBuilder<T> builder,
  DSheetSide side = DSheetSide.right,
  double sidePanelMaxWidth = 384,
  double? sidePanelWidth,
  bool inset = false,
  bool animateSize = false,
  bool useRootNavigator = false,
  bool dismissOnBarrier = true,
  bool dismissOnEscape = true,
  String barrierLabel = 'Dismiss sheet',
  RouteSettings? routeSettings,
  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
}) {
  assert(sidePanelMaxWidth > 0);
  assert(sidePanelWidth == null || sidePanelWidth > 0);
  return showDDialog<T>(
    context: context,
    builder: builder,
    useRootNavigator: useRootNavigator,
    dismissOnBarrier: dismissOnBarrier,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    routeSettings: routeSettings,
    initialFocusNode: initialFocusNode,
    finalFocusNode: finalFocusNode,
    presentationBuilder: (context, presentation) => _sheetPresentation(
      context,
      presentation,
      side,
      sidePanelMaxWidth,
      sidePanelWidth,
      inset,
      animateSize,
    ),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
  );
}
