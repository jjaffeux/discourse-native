import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_dialog.dart';

/// Physical edges, direction-aware conveniences, and a centered reading panel.
enum DSheetSide { top, right, bottom, left, start, end, center }

extension on DSheetSide {
  DSheetSide resolve(TextDirection direction) => switch (this) {
    DSheetSide.start =>
      direction == TextDirection.ltr ? DSheetSide.left : DSheetSide.right,
    DSheetSide.end =>
      direction == TextDirection.ltr ? DSheetSide.right : DSheetSide.left,
    _ => this,
  };

  bool get isHorizontal =>
      this == DSheetSide.left ||
      this == DSheetSide.right ||
      this == DSheetSide.center;
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
    this.onOpenChangeComplete,
    this.useRootNavigator = false,
    this.modal = true,
    this.dismissOnBarrier = true,
    this.dismissOnEscape = true,
    this.barrierLabel = 'Dismiss sheet',
    this.routeSettings,
    this.initialFocusNode,
    this.finalFocusNode,
    this.restoreFocus = true,
  }) : assert(open == null || !initiallyOpen);

  final DSheetTrigger trigger;
  final DSheetContent content;
  final DSheetController<T>? controller;
  final bool? open;
  final bool initiallyOpen;
  final ValueChanged<DSheetChangeDetails<T>>? onOpenChanged;

  /// Called when the opening or closing transition finishes.
  final ValueChanged<bool>? onOpenChangeComplete;
  final bool useRootNavigator;

  /// Allows interaction with the exposed background without dismissing the
  /// sheet when false. Modal sheets retain their dimmed, blurred backdrop.
  final bool modal;
  final bool dismissOnBarrier;
  final bool dismissOnEscape;
  final String barrierLabel;
  final RouteSettings? routeSettings;
  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;

  /// Restores focus to the trigger or previous control after dismissal.
  final bool restoreFocus;

  @override
  Widget build(BuildContext context) => DDialog<T>(
    controller: controller,
    open: open,
    initiallyOpen: initiallyOpen,
    onOpenChanged: onOpenChanged,
    onOpenChangeComplete: onOpenChangeComplete,
    useRootNavigator: useRootNavigator,
    modal: modal,
    dismissOnBarrier: dismissOnBarrier,
    dismissOnEscape: dismissOnEscape,
    barrierLabel: barrierLabel,
    routeSettings: routeSettings,
    initialFocusNode: initialFocusNode,
    finalFocusNode: finalFocusNode,
    restoreFocus: restoreFocus,
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
      content.fillAvailableHeight,
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

// A CurvedAnimation holds a status listener on the route animation until it
// is disposed, so the sheet's curves are owned by a State rather than rebuilt
// with every inset or configuration change of the open sheet.
class _DSheetCurves extends StatefulWidget {
  const _DSheetCurves({required this.animation, required this.builder});

  final Animation<double> animation;
  final Widget Function(
    BuildContext context,
    Animation<double> popupCurve,
    Animation<double> backdropCurve,
  )
  builder;

  @override
  State<_DSheetCurves> createState() => _DSheetCurvesState();
}

class _DSheetCurvesState extends State<_DSheetCurves> {
  late CurvedAnimation _popup;
  late CurvedAnimation _backdrop;

  @override
  void initState() {
    super.initState();
    _create();
  }

  void _create() {
    _popup = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeInOut,
    );
    _backdrop = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0, .75, curve: Curves.easeInOut),
      reverseCurve: const Interval(.25, 1, curve: Curves.easeInOut),
    );
  }

  void _dispose() {
    _popup.dispose();
    _backdrop.dispose();
  }

  @override
  void didUpdateWidget(_DSheetCurves oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.animation, widget.animation)) return;
    _dispose();
    _create();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _popup, _backdrop);
}

Widget _sheetPresentation(
  BuildContext context,
  DDialogPresentation presentation,
  DSheetSide requestedSide,
  double maxWidth,
  double? width,
  bool inset,
  bool animateSize,
  bool fillAvailableHeight,
) => _DSheetCurves(
  animation: presentation.animation,
  builder: (context, popupCurve, backdropCurve) => _sheetLayout(
    context,
    presentation,
    popupCurve,
    backdropCurve,
    requestedSide,
    maxWidth,
    width,
    inset,
    animateSize,
    fillAvailableHeight,
  ),
);

Widget _sheetLayout(
  BuildContext context,
  DDialogPresentation presentation,
  Animation<double> popupCurve,
  Animation<double> backdropCurve,
  DSheetSide requestedSide,
  double maxWidth,
  double? width,
  bool inset,
  bool animateSize,
  bool fillAvailableHeight,
) {
  final animate = !MediaQuery.disableAnimationsOf(context);
  final side = requestedSide.resolve(Directionality.of(context));
  Widget backdrop = fillAvailableHeight
      ? presentation.buildBackdrop(
          color: DTokens.of(context).background.withValues(alpha: 1),
          blurSigma: 0,
        )
      : presentation.buildBackdrop(blurSigma: 2);
  if (animate && !fillAvailableHeight) {
    backdrop = FadeTransition(opacity: backdropCurve, child: backdrop);
  }

  final beginOffset = switch (side) {
    DSheetSide.center => const Offset(0, 40),
    DSheetSide.top => const Offset(0, -40),
    DSheetSide.right => const Offset(40, 0),
    DSheetSide.bottom => const Offset(0, 40),
    DSheetSide.left => const Offset(-40, 0),
    _ => throw StateError('Sheet side was not resolved.'),
  };
  Widget popup = _DSheetSideScope(
    side: side,
    inset: inset,
    child: fillAvailableHeight
        ? MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Builder(
              builder: (context) => MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: presentation.content,
              ),
            ),
          )
        : presentation.content,
  );
  if (animate) {
    if (fillAvailableHeight) {
      popup = ScaleTransition(
        scale: Tween<double>(begin: .97, end: 1).animate(popupCurve),
        child: popup,
      );
    }
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

  final layout = LayoutBuilder(
    builder: (context, bounds) {
      final margin = inset ? DSpacing.md : 0.0;
      // A trigger inside SafeArea can capture a MediaQuery with its top padding
      // consumed, even though the overlay route covers the whole screen.
      final view = View.of(context);
      final safeTop = math.max(
        MediaQuery.paddingOf(context).top,
        view.viewPadding.top / view.devicePixelRatio,
      );
      final pickerTop = math.max(safeTop + DSpacing.xl, bounds.maxHeight * .11);
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
        left: side == DSheetSide.center
            ? (bounds.maxWidth - panelWidth) / 2
            : side == DSheetSide.right
            ? null
            : margin,
        right: side == DSheetSide.left || side == DSheetSide.center
            ? null
            : margin,
        top: fillAvailableHeight
            ? pickerTop
            : side == DSheetSide.bottom
            ? null
            : margin,
        bottom: fillAvailableHeight
            ? MediaQuery.viewInsetsOf(context).bottom + margin
            : side == DSheetSide.top
            ? null
            : margin,
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
  return fillAvailableHeight ? _DSheetKeyboardInsets(child: layout) : layout;
}

// Scaffold can consume the opening control's keyboard inset. Observe the view
// so a full-height sheet still resizes as the keyboard opens and closes, while
// preserving the caller's other MediaQuery overrides.
class _DSheetKeyboardInsets extends StatelessWidget {
  const _DSheetKeyboardInsets({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery.fromView(
      view: View.of(context),
      child: Builder(
        builder: (viewContext) => MediaQuery(
          data: media.copyWith(
            viewInsets: media.viewInsets.copyWith(
              bottom: math.max(
                media.viewInsets.bottom,
                MediaQuery.viewInsetsOf(viewContext).bottom,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
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
    this.backgroundColor,
    this.sidePanelMaxWidth = 384,
    this.sidePanelWidth,
    this.inset = false,
    this.animateSize = false,
    this.sideAccessory,
    this.sideAccessoryWidth = 52,
    this.scrollWholeSheet,
    this.topBottomMaxHeightFactor,
    this.fillAvailableHeight = false,
  }) : assert(sideAccessoryWidth > 0),
       assert(
         sideAccessory == null ||
             (side != DSheetSide.top && side != DSheetSide.bottom),
       ),
       assert(sidePanelMaxWidth > 0),
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

  /// Overrides the surface fill. Defaults to [DTokens.surface].
  final Color? backgroundColor;

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

  /// Optional controls beside the surface, on the inward-facing edge.
  ///
  /// Supported on side sheets only. The gutter is inside the panel width and
  /// shares its route, focus scope and motion, but stays outside its decoration.
  final Widget? sideAccessory;

  /// Space reserved for [sideAccessory], including its horizontal breathing room.
  /// Both this gutter and the surface must fit inside [sidePanelWidth].
  final double sideAccessoryWidth;

  /// Overrides automatic whole-surface scrolling at large text sizes.
  ///
  /// Null preserves the default. Set false only when a composed child owns a
  /// bounded scroll region while its surrounding header and footer stay fixed.
  final bool? scrollWholeSheet;

  /// Optional cap used by long top and bottom compositions.
  final double? topBottomMaxHeightFactor;

  /// Fills the viewport above the keyboard with space above the sheet.
  /// The top gap is at least 11% of the viewport and 24px below the safe area.
  final bool fillAvailableHeight;

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
            DSheetSide.center => Border.all(color: tokens.border),
            DSheetSide.top => Border(bottom: edgeBorder),
            DSheetSide.right => Border(left: edgeBorder),
            DSheetSide.bottom => Border(top: edgeBorder),
            DSheetSide.left => Border(right: edgeBorder),
            _ => throw StateError('Sheet side was not resolved.'),
          };
    final radius = inset
        ? BorderRadius.circular(DRadius.panel)
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
          color: backgroundColor ?? tokens.surface,
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
    if (sideAccessory case final accessory?) {
      final gutter = SizedBox(
        width: sideAccessoryWidth,
        child: Center(child: accessory),
      );
      surface = Row(
        textDirection: TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resolved == DSheetSide.right || resolved == DSheetSide.center)
            gutter,
          Expanded(key: const ValueKey('sheet-surface'), child: surface),
          if (resolved == DSheetSide.left) gutter,
        ],
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
  bool fillAvailableHeight = false,
  bool useRootNavigator = false,
  bool modal = true,
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
    modal: modal,
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
      fillAvailableHeight,
    ),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
  );
}
