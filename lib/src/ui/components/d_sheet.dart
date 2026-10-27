import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/d_overlay_route.dart';
import '../foundation/sheet_content_gesture_scope.dart';
import '../foundation/surface_depth.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_dialog.dart';
import 'd_mobile_dock_geometry.dart';
import 'd_page_surface.dart';

part 'd_sheet_adaptive_menu.dart';

/// Sheet artwork presets. Menu sheets float above the home indicator with
/// a grab handle and rounded corners matching anchored Native menus.
enum DSheetVariant {
  standard,
  menu,

  /// A bottom reading page filling [DSheetViewport], with an overlaid handle.
  page,

  /// A mobile menu with a lower opening height, pull-to-expand, and animated
  /// clearance while expanding, when the keyboard is visible, or when there
  /// is no more content below.
  adaptiveMenu,
}

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

    this.onOpenChanged,
    this.onOpenChangeComplete,

    this._barrierLabel,

    this.initialFocusNode,
    this.finalFocusNode,
    this.restoreFocus = true,
  });

  final DSheetTrigger trigger;
  final DSheetContent content;
  final DSheetController<T>? controller;
  final bool? open;

  final ValueChanged<DSheetChangeDetails<T>>? onOpenChanged;

  /// Called when the opening or closing transition finishes.
  final ValueChanged<bool>? onOpenChangeComplete;

  final String? _barrierLabel;
  String get barrierLabel => _barrierLabel ?? appL10n.dismissSheet;

  final FocusNode? initialFocusNode;
  final FocusNode? finalFocusNode;

  /// Restores focus to the trigger or previous control after dismissal.
  final bool restoreFocus;

  @override
  Widget build(BuildContext context) => DDialog<T>(
    controller: controller,
    open: open,
    initiallyOpen: false,
    onOpenChanged: onOpenChanged,
    onOpenChangeComplete: onOpenChangeComplete,
    useRootNavigator: false,
    modal: true,
    dismissOnBarrier: true,
    dismissOnEscape: true,
    barrierLabel: barrierLabel,
    routeSettings: null,
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
      false,
      content.fillAvailableHeight,
      content.extendBehindKeyboard,
      true,
      variant: content.variant,
      sizeToContent: content.sizeToContent,
      contentLoading: content.contentLoading,
    ),
    trigger: DDialogTrigger(builder: trigger.builder),
    content: content,
  );
}

/// Sheet presentation for a retained surface whose host owns its visibility.
///
/// Mount in a full viewport outside a resizing [Scaffold]. The host owns back
/// handling and excludes the covered content from focus and semantics. Hide
/// [DSheetContent.showCloseButton] or compose a close action with
/// the host's close action; route-owned [DSheetClose] is unavailable here.
class DSheetViewport extends StatelessWidget {
  const DSheetViewport({
    super.key,
    required this.content,

    this.onDismiss,
    this.onSwipeDismissRequested,
    this.underlay,
    this.covering,
  });

  final DSheetContent content;

  /// The previous page, painted only while a page sheet is pulled down.
  /// Focus, semantics and input stay excluded throughout the reveal.
  final Widget? underlay;

  /// Called after a downward swipe finishes moving the sheet off-screen.
  ///
  /// The host can remove the sheet or leave it mounted to return it to its
  /// open position.
  final VoidCallback? onDismiss;

  /// Intercepts a swipe as soon as it reaches the dismissal threshold.
  ///
  /// The sheet immediately returns to its open position and consumes the rest
  /// of the gesture. This callback runs after layout, allowing the host to open
  /// an anchored confirmation or action menu. Takes precedence over [onDismiss].
  final VoidCallback? onSwipeDismissRequested;

  /// True while a full-height sheet's opaque canvas hides everything beneath
  /// it, false while a swipe reveals it and once the sheet is gone. A host
  /// that draws the covered content outside this viewport can skip painting
  /// it while this is true. It changes during the frame that changes it,
  /// including while the sheet builds and unmounts, so read it when painting.
  final ValueNotifier<bool>? covering;

  @override
  Widget build(BuildContext context) {
    assert((!content.showCloseButton));
    return FocusScope(
      child: _sheetPresentation(
        context,
        DDialogPresentation(
          content: content,
          animation: const AlwaysStoppedAnimation(1),
          barrierLabel: context.l10n.sheetBackground,
          dismissOnBarrier: false,
          onBarrierDismiss: () {},
        ),
        content.side,
        content.sidePanelMaxWidth,
        content.sidePanelWidth,
        content.inset,
        false,
        content.fillAvailableHeight,
        content.extendBehindKeyboard,
        onDismiss != null || onSwipeDismissRequested != null,
        variant: content.variant,
        sizeToContent: content.sizeToContent,
        contentLoading: content.contentLoading,
        retainKeyboardInsets: true,
        onRetainedDismiss: onDismiss,
        onRetainedSwipeDismissRequested: onSwipeDismissRequested,
        underlay: underlay,
        covering: covering,
      ),
    );
  }
}

/// Where the content of a page sheet says what its condensed head is doing
/// over the sheet's top edge. A head that is a band of its own fill across
/// that edge is the sheet's top while it rests there.
abstract interface class DSheetPageBand {
  /// [owner] is the head reporting; a later report from it replaces this one.
  /// [resting]: the band sits whole over the top edge. [coversGrabber]: enough
  /// of it is still there to cover the grabber.
  void report(
    Object owner, {
    required bool resting,
    required bool coversGrabber,
  });

  /// [owner] no longer has a band over the sheet.
  void withdraw(Object owner);

  /// The page sheet [context] is in, if any.
  static DSheetPageBand? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DSheetPageBandScope>()?.band;
}

class _DSheetPageBandScope extends InheritedWidget {
  const _DSheetPageBandScope({required this.band, required super.child});

  final DSheetPageBand band;

  @override
  bool updateShouldNotify(_DSheetPageBandScope oldWidget) =>
      band != oldWidget.band;
}

/// A page sheet's card: round at its top as the phone's bar is, squared under
/// a band resting there, whose antialiased edge would otherwise let a sliver
/// of the card show along the curve the two share. The grabber is drawn under
/// the band while the band covers it.
class _DSheetPageCard extends StatefulWidget {
  const _DSheetPageCard({
    required this.color,
    required this.handle,
    required this.children,
  });

  final Color color;
  final Widget handle;
  final List<Widget> children;

  @override
  State<_DSheetPageCard> createState() => _DSheetPageCardState();
}

class _DSheetPageCardState extends State<_DSheetPageCard>
    implements DSheetPageBand {
  Object? _owner;
  bool _resting = false;
  bool _coversGrabber = false;

  // A head's reports can still be waiting for the frame when it withdraws.
  final _withdrawn = Expando<bool>();

  @override
  void report(
    Object owner, {
    required bool resting,
    required bool coversGrabber,
  }) {
    if (_withdrawn[owner] == true) return;
    _apply(owner, resting: resting, coversGrabber: coversGrabber);
  }

  @override
  void withdraw(Object owner) {
    _withdrawn[owner] = true;
    _apply(owner, resting: false, coversGrabber: false);
  }

  // Reports arrive from scroll ticks, layout and unmounting, so the change
  // waits for the frame's build to be over.
  void _apply(
    Object owner, {
    required bool resting,
    required bool coversGrabber,
  }) {
    final withdrawing = _withdrawn[owner] == true;
    void commit() {
      if (!mounted) return;
      if (withdrawing ? !identical(owner, _owner) : _withdrawn[owner] == true) {
        return;
      }
      if (identical(owner, _owner) &&
          resting == _resting &&
          coversGrabber == _coversGrabber) {
        return;
      }
      setState(() {
        _owner = owner;
        _resting = resting;
        _coversGrabber = coversGrabber;
      });
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.transientCallbacks) {
      commit();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => commit());
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = Radius.circular(
      _resting ? 0 : DMobileDockGeometry.capsuleRadius,
    );
    return _DSheetPageBandScope(
      band: this,
      child: DPageSurface(
        border: false,
        borderRadius: BorderRadius.vertical(
          top: top,
          bottom: const Radius.circular(22),
        ),
        backgroundColor: widget.color,
        depth: DSurfaceDepth.panel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Visibility(
                visible: !_coversGrabber,
                maintainState: true,
                child: widget.handle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DSheetPagePullScope extends InheritedWidget {
  const _DSheetPagePullScope({required this.pulled, required super.child});

  final bool pulled;

  @override
  bool updateShouldNotify(_DSheetPagePullScope oldWidget) =>
      pulled != oldWidget.pulled;
}

// A retained sheet stays visible beneath picker routes. Its keyboard belongs
// to its own editor, so another route's focus handoff must not resize it.
class _DSheetRetainedKeyboardInsets extends StatefulWidget {
  const _DSheetRetainedKeyboardInsets({required this.child});

  final Widget child;

  @override
  State<_DSheetRetainedKeyboardInsets> createState() =>
      _DSheetRetainedKeyboardInsetsState();
}

class _DSheetRetainedKeyboardInsetsState
    extends State<_DSheetRetainedKeyboardInsets> {
  EdgeInsets? _insets;
  EdgeInsets? _padding;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: DOverlayRoute.modalCoverCountOf(context),
    builder: (context, covers, child) {
      final media = MediaQuery.of(context);
      if (covers == 0 || _insets == null) {
        _insets = media.viewInsets;
        _padding = media.padding;
      }
      return DOverlayKeyboardMetrics(
        viewInsets: media.viewInsets,
        padding: media.padding,
        child: MediaQuery(
          data: media.copyWith(viewInsets: _insets, padding: _padding),
          child: child!,
        ),
      );
    },
    child: widget.child,
  );
}

class _DSheetSideScope extends InheritedWidget {
  const _DSheetSideScope({
    required this.side,
    required this.inset,
    required this.fillAvailableHeight,
    required this.extendBehindKeyboard,
    this.menuInsetProgress,
    required super.child,
  });

  final DSheetSide side;
  final bool inset;
  final bool fillAvailableHeight;
  final bool extendBehindKeyboard;
  final double? menuInsetProgress;

  static DSheetSide? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DSheetSideScope>()?.side;

  static bool? insetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DSheetSideScope>()?.inset;

  static bool? fillsAvailableHeightOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DSheetSideScope>()
      ?.fillAvailableHeight;

  static bool? extendsBehindKeyboardOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DSheetSideScope>()
      ?.extendBehindKeyboard;

  @override
  bool updateShouldNotify(_DSheetSideScope oldWidget) =>
      side != oldWidget.side ||
      inset != oldWidget.inset ||
      menuInsetProgress != oldWidget.menuInsetProgress ||
      fillAvailableHeight != oldWidget.fillAvailableHeight ||
      extendBehindKeyboard != oldWidget.extendBehindKeyboard;
}

// A CurvedAnimation holds a status listener on the route animation until it
// is disposed, so the sheet's curves are owned by a State rather than rebuilt
// with every inset or configuration change of the open sheet.
class _DSheetCurves extends StatefulWidget {
  const _DSheetCurves({
    required this.animation,
    required this.opaque,
    this.covering,
    required this.builder,
  });

  final Animation<double> animation;

  /// Whether the backdrop is an opaque canvas until a swipe fades it.
  final bool opaque;
  final ValueNotifier<bool>? covering;
  final Widget Function(
    BuildContext context,
    Animation<double> popupCurve,
    Animation<double> backdropCurve,
    ValueNotifier<double> swipeProgress,
    GlobalKey<_DSheetSwipeDismissState> swipeKey,
  )
  builder;

  @override
  State<_DSheetCurves> createState() => _DSheetCurvesState();
}

class _DSheetCurvesState extends State<_DSheetCurves> {
  late CurvedAnimation _popup;
  late CurvedAnimation _backdrop;
  final _swipeProgress = ValueNotifier(0.0);
  final _swipeKey = GlobalKey<_DSheetSwipeDismissState>();

  @override
  void initState() {
    super.initState();
    _create();
    _swipeProgress.addListener(_syncCovering);
    _syncCovering();
  }

  void _syncCovering() {
    widget.covering?.value = widget.opaque && _swipeProgress.value == 0;
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
    if (oldWidget.covering != widget.covering) {
      oldWidget.covering?.value = false;
    }
    _syncCovering();
    if (identical(oldWidget.animation, widget.animation)) return;
    _dispose();
    _create();
  }

  @override
  void dispose() {
    widget.covering?.value = false;
    _dispose();
    _swipeProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _popup, _backdrop, _swipeProgress, _swipeKey);
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
  bool extendBehindKeyboard,
  bool dismissOnSwipe, {
  DSheetVariant variant = DSheetVariant.standard,
  bool sizeToContent = true,
  bool contentLoading = false,
  double? topBottomMaxWidth,
  bool retainKeyboardInsets = false,
  VoidCallback? onRetainedDismiss,
  VoidCallback? onRetainedSwipeDismissRequested,
  Widget? underlay,
  ValueNotifier<bool>? covering,
}) {
  if (variant == DSheetVariant.adaptiveMenu &&
      requestedSide == DSheetSide.bottom) {
    Widget menu(VoidCallback? close) => _DSheetAdaptiveMenu(
      presentation: presentation,
      onDismiss: dismissOnSwipe ? close : null,
      retained: retainKeyboardInsets,
      onDismissRequested: onRetainedSwipeDismissRequested,
      sizeToContent: sizeToContent,
      contentLoading: contentLoading,
    );
    return _DSheetKeyboardInsets(
      child: retainKeyboardInsets
          ? _DSheetRetainedKeyboardInsets(child: menu(onRetainedDismiss))
          : DSheetClose<void>(builder: (context, close) => menu(close)),
    );
  }
  return _DSheetCurves(
    animation: presentation.animation,
    // Matches the backdrop _sheetLayout draws for full-height sheets.
    opaque:
        presentation.modal &&
        fillAvailableHeight &&
        variant != DSheetVariant.page,
    covering: covering,
    builder: (context, popupCurve, backdropCurve, swipeProgress, swipeKey) =>
        _sheetLayout(
          context,
          presentation,
          popupCurve,
          backdropCurve,
          swipeProgress,
          swipeKey,
          requestedSide,
          maxWidth,
          width,
          inset,
          animateSize,
          fillAvailableHeight,
          extendBehindKeyboard,
          dismissOnSwipe,
          variant: variant,
          topBottomMaxWidth: topBottomMaxWidth,
          retainKeyboardInsets: retainKeyboardInsets,
          onRetainedDismiss: onRetainedDismiss,
          onRetainedSwipeDismissRequested: onRetainedSwipeDismissRequested,
          underlay: underlay,
        ),
  );
}

Widget _sheetLayout(
  BuildContext context,
  DDialogPresentation presentation,
  Animation<double> popupCurve,
  Animation<double> backdropCurve,
  ValueNotifier<double> swipeProgress,
  GlobalKey<_DSheetSwipeDismissState> swipeKey,
  DSheetSide requestedSide,
  double maxWidth,
  double? width,
  bool inset,
  bool animateSize,
  bool fillAvailableHeight,
  bool extendBehindKeyboard,
  bool dismissOnSwipe, {
  DSheetVariant variant = DSheetVariant.standard,
  double? topBottomMaxWidth,
  bool retainKeyboardInsets = false,
  VoidCallback? onRetainedDismiss,
  VoidCallback? onRetainedSwipeDismissRequested,
  Widget? underlay,
}) {
  final page = variant == DSheetVariant.page;
  final animate = !MediaQuery.disableAnimationsOf(context);
  final side = requestedSide.resolve(Directionality.of(context));
  final background = DTokens.of(context).background.withValues(alpha: 1);
  // Full-height sheets start with an opaque canvas. A swipe reveals the
  // underlying application as the sheet moves out of the viewport.
  final backdropColor = Color.lerp(
    background,
    Colors.black,
    Theme.of(context).brightness == Brightness.dark ? .32 : .12,
  )!;
  Widget backdrop = page
      ? (underlay == null
            ? const SizedBox.expand()
            : ExcludeFocus(
                child: ExcludeSemantics(
                  child: IgnorePointer(child: ClipRect(child: underlay)),
                ),
              ))
      : fillAvailableHeight
      ? presentation.buildBackdrop(color: backdropColor)
      : presentation.buildBackdrop();
  if (animate && !fillAvailableHeight && !page) {
    backdrop = FadeTransition(opacity: backdropCurve, child: backdrop);
  }
  backdrop = ValueListenableBuilder<double>(
    valueListenable: swipeProgress,
    builder: (context, progress, child) => page
        ? Offstage(
            offstage: progress <= 0,
            child: TickerMode(enabled: progress > 0, child: child!),
          )
        : Opacity(opacity: 1 - progress, child: child),
    child: backdrop,
  );

  final beginOffset = switch (side) {
    DSheetSide.center => const Offset(0, 40),
    DSheetSide.top => const Offset(0, -40),
    DSheetSide.right => const Offset(40, 0),
    DSheetSide.bottom => const Offset(0, 40),
    DSheetSide.left => const Offset(-40, 0),
    _ => throw StateError('Sheet side was not resolved.'),
  };
  final content = inset && !extendBehindKeyboard
      ? Builder(
          builder: (context) => MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: presentation.content,
          ),
        )
      : presentation.content;
  Widget popup = _DSheetSideScope(
    side: side,
    inset: inset,
    fillAvailableHeight: fillAvailableHeight,
    extendBehindKeyboard: extendBehindKeyboard,
    child: extendBehindKeyboard
        ? Builder(
            builder: (context) => MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: content,
            ),
          )
        : fillAvailableHeight
        ? MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Builder(
              builder: (context) => MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: content,
              ),
            ),
          )
        : content,
  );
  if (page) {
    popup = ValueListenableBuilder<double>(
      valueListenable: swipeProgress,
      builder: (context, progress, child) =>
          _DSheetPagePullScope(pulled: progress > 0, child: child!),
      child: popup,
    );
  }
  final mobile = switch (Theme.of(context).platform) {
    TargetPlatform.iOS ||
    TargetPlatform.android ||
    TargetPlatform.fuchsia => true,
    _ => false,
  };
  if (dismissOnSwipe && (mobile || page) && side == DSheetSide.bottom) {
    if (presentation.modal) {
      // The backdrop owns outside gestures; the sheet keeps its own bounds.
      // Forward to the same motion owner so threshold, cancellation and exit
      // velocity agree with a drag begun on the sheet itself. Pointer cancel
      // restores the sheet before an accepted drag emits its end callback.
      backdrop = Listener(
        onPointerDown: (event) => swipeKey.currentState?._onPointerDown(event),
        onPointerMove: (event) => swipeKey.currentState?._onPointerMove(event),
        onPointerUp: (event) => swipeKey.currentState?._onPointerUp(event),
        onPointerCancel: (event) =>
            swipeKey.currentState?._onPointerCancel(event),
        child: GestureDetector(
          excludeFromSemantics: true,
          supportedDevices: const {PointerDeviceKind.touch},
          onVerticalDragStart: (_) => swipeKey.currentState?._start(),
          onVerticalDragUpdate: (details) =>
              swipeKey.currentState?._update(details.delta.dy),
          onVerticalDragEnd: (details) =>
              swipeKey.currentState?._finish(details.primaryVelocity ?? 0),
          onVerticalDragCancel: () =>
              swipeKey.currentState?._finish(0, cancelled: true),
          child: backdrop,
        ),
      );
    }
    final content = popup;
    Widget swipe(VoidCallback? close, {bool retained = false}) =>
        _DSheetSwipeDismiss(
          key: swipeKey,
          onDismiss: close,
          onDismissRequested: retained ? onRetainedSwipeDismissRequested : null,
          retained: retained,
          routeAnimation: presentation.animation,
          popupCurve: popupCurve,
          scale: fillAvailableHeight,
          swipeProgress: swipeProgress,
          page: page,
          child: content,
        );
    popup = onRetainedDismiss != null || onRetainedSwipeDismissRequested != null
        ? swipe(onRetainedDismiss, retained: true)
        : DSheetClose<void>(builder: (context, close) => swipe(close));
  } else {
    popup = _DSheetMotion(
      curve: popupCurve,
      beginOffset: beginOffset,
      scale: fillAvailableHeight,
      child: popup,
    );
  }

  final layout = LayoutBuilder(
    builder: (context, bounds) {
      if (page) {
        return Stack(fit: StackFit.expand, children: [backdrop, popup]);
      }
      final margin = inset
          ? variant == DSheetVariant.menu
                ? 6.0
                : DSpacing.md
          : 0.0;
      // A trigger inside SafeArea can capture a MediaQuery with its top padding
      // consumed, even though the overlay route covers the whole screen.
      final view = View.of(context);
      final safeTop = math.max(
        MediaQuery.paddingOf(context).top,
        view.viewPadding.top / view.devicePixelRatio,
      );
      // Inset surfaces float above the device's bottom corners. The opening
      // control may already have consumed this padding inside a SafeArea.
      final safeBottom = inset && !extendBehindKeyboard
          ? math.max(
              MediaQuery.viewPaddingOf(context).bottom,
              view.viewPadding.bottom / view.devicePixelRatio,
            )
          : 0.0;
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
      final topBottomWidth = !horizontal && topBottomMaxWidth != null
          ? topBottomMaxWidth.clamp(0.0, availableWidth).toDouble()
          : null;
      final positioned = AnimatedPositioned(
        duration: animateSize
            ? DMotion.duration(context, DMotion.change)
            : Duration.zero,
        curve: Curves.easeOutCubic,
        left: topBottomWidth != null
            ? (bounds.maxWidth - topBottomWidth) / 2
            : side == DSheetSide.center
            ? (bounds.maxWidth - panelWidth) / 2
            : side == DSheetSide.right
            ? null
            : margin,
        right:
            topBottomWidth != null ||
                side == DSheetSide.left ||
                side == DSheetSide.center
            ? null
            : margin,
        top: extendBehindKeyboard
            ? safeTop + DSpacing.sm
            : fillAvailableHeight
            ? pickerTop
            : side == DSheetSide.bottom
            ? null
            : margin,
        bottom: fillAvailableHeight
            ? (extendBehindKeyboard
                      ? 0.0
                      : math.max(
                          MediaQuery.viewInsetsOf(context).bottom,
                          safeBottom,
                        )) +
                  margin
            : side == DSheetSide.top
            ? null
            : margin + safeBottom,
        width: horizontal ? panelWidth : topBottomWidth,
        child: variant == DSheetVariant.menu && side == DSheetSide.bottom
            ? ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(
                    0,
                    bounds.maxHeight -
                        safeTop -
                        DSpacing.sm -
                        safeBottom -
                        margin,
                  ),
                ),
                child: popup,
              )
            : popup,
      );
      return Stack(
        children: [
          Positioned.fill(child: backdrop),
          positioned,
        ],
      );
    },
  );
  return fillAvailableHeight
      ? _DSheetKeyboardInsets(
          child: retainKeyboardInsets
              ? _DSheetRetainedKeyboardInsets(child: layout)
              : layout,
        )
      : layout;
}

class _DSheetMotion extends StatelessWidget {
  const _DSheetMotion({
    required this.curve,
    required this.beginOffset,
    required this.scale,
    required this.child,
  });

  final Animation<double> curve;
  final Offset beginOffset;
  final bool scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final motion = AnimatedBuilder(
      animation: curve,
      child: scale
          ? ScaleTransition(
              scale: Tween<double>(begin: .97, end: 1).animate(curve),
              child: child,
            )
          : child,
      builder: (context, child) => Transform.translate(
        offset: Offset.lerp(beginOffset, Offset.zero, curve.value)!,
        child: child,
      ),
    );
    return FadeTransition(opacity: curve, child: motion);
  }
}

const _sheetDismissFraction = .3;

// Start the exit at the release velocity and accelerate slow swipes to finish
// within the requested duration; faster swipes retain their speed.
class _DSheetDismissSimulation extends Simulation {
  _DSheetDismissSimulation(
    this.distance,
    this.velocity,
    this.initialValue, {
    this.endValue = 0,
    double duration = .32,
  }) : acceleration = math.max(
         0,
         2 * (distance - velocity * duration) / (duration * duration),
       );

  final double distance;
  final double velocity;
  final double initialValue;
  final double endValue;
  final double acceleration;

  double _progress(double time) =>
      (velocity * time + acceleration * time * time / 2) / distance;

  @override
  double x(double time) =>
      initialValue + (endValue - initialValue) * _progress(time).clamp(0, 1);

  @override
  double dx(double time) =>
      (endValue - initialValue) * (velocity + acceleration * time) / distance;

  @override
  bool isDone(double time) => _progress(time) >= 1;
}

/// A visible sheet region that drags the sheet independently of body scrolling.
///
/// Wrap a pinned header to allow dismissal even when its scrollable ancestor
/// is away from the top. In sheets without swipe dismissal this is inert.
class DSheetDragRegion extends StatelessWidget {
  const DSheetDragRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final menuScope = context
        .dependOnInheritedWidgetOfExactType<_DSheetAdaptiveMenuScope>();
    if (menuScope != null) {
      final menu = menuScope.menu;
      return Semantics(
        button: menuScope.canCollapse,
        label: menuScope.canCollapse
            ? (menuScope.expanded ? context.l10n.collapse : context.l10n.expand)
            : null,
        onTap: menuScope.canCollapse ? menu._toggle : null,
        child: GestureDetector(
          onTap: menuScope.canCollapse ? menu._toggle : null,
          supportedDevices: const {PointerDeviceKind.touch},
          onVerticalDragStart: (_) => menu._start(),
          onVerticalDragUpdate: (details) => menu._update(details.delta.dy),
          onVerticalDragEnd: (details) =>
              menu._finish(details.primaryVelocity ?? 0),
          onVerticalDragCancel: () => menu._finish(0, cancelled: true),
          child: child,
        ),
      );
    }
    final swipe = context
        .dependOnInheritedWidgetOfExactType<_DSheetSwipeScope>()
        ?.swipe;
    if (swipe == null) return child;
    return Listener(
      onPointerDown: swipe._claimHandlePointer,
      onPointerPanZoomStart: swipe.widget.page
          ? swipe._claimHandlePointer
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: swipe.widget.page
            ? const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              }
            : const {PointerDeviceKind.touch},
        onVerticalDragStart: (_) => swipe._start(),
        onVerticalDragUpdate: (details) => swipe._update(details.delta.dy),
        onVerticalDragEnd: (details) =>
            swipe._finish(details.primaryVelocity ?? 0),
        onVerticalDragCancel: () => swipe._finish(0, cancelled: true),
        child: child,
      ),
    );
  }
}

class _DSheetSwipeScope extends InheritedWidget {
  const _DSheetSwipeScope({required this.swipe, required super.child});

  final _DSheetSwipeDismissState swipe;

  @override
  bool updateShouldNotify(_DSheetSwipeScope oldWidget) =>
      swipe != oldWidget.swipe;
}

class _DSheetSwipeDismiss extends StatefulWidget {
  const _DSheetSwipeDismiss({
    super.key,
    required this.onDismiss,
    this.onDismissRequested,
    required this.retained,
    required this.routeAnimation,
    required this.popupCurve,
    required this.scale,
    required this.swipeProgress,
    this.page = false,
    required this.child,
  });

  final VoidCallback? onDismiss;
  final VoidCallback? onDismissRequested;
  final bool retained;
  final Animation<double> routeAnimation;
  final Animation<double> popupCurve;
  final bool scale;
  final ValueNotifier<double> swipeProgress;
  final bool page;
  final Widget child;

  @override
  State<_DSheetSwipeDismiss> createState() => _DSheetSwipeDismissState();
}

enum _DSheetPointerOwner { sheet, content, handle }

class _DSheetSwipeDismissState extends State<_DSheetSwipeDismiss>
    with SingleTickerProviderStateMixin {
  late final _travel = AnimationController.unbounded(vsync: this);
  int? _pointer;
  _DSheetPointerOwner _pointerOwner = _DSheetPointerOwner.sheet;
  PointerEvent? _contentSignal;
  VelocityTracker? _velocity;
  BuildContext? _scrollOrigin;
  bool _dragging = false;
  bool _exiting = false;
  bool _swipeIntercepted = false;
  DOverlayRoute<dynamic, Object>? _route;
  Simulation? Function()? _pendingSimulation;
  _DSheetDismissSimulation? _dismissal;
  double _dismissOrigin = 0;
  double _dismissCurve = 1;
  double _swipeExtent = 1;
  final _scrollPositions = <ScrollPosition, BuildContext>{};
  Timer? _wheelEnd;
  bool _wheeling = false;
  DateTime? _wheelSpentUntil;

  void _rememberScroll(BuildContext? origin) {
    if (!widget.page || origin == null) return;
    final scrollable = Scrollable.maybeOf(origin, axis: Axis.vertical);
    if (scrollable != null) _scrollPositions[scrollable.position] = origin;
  }

  bool _atTop(Offset point) {
    _scrollPositions.removeWhere((_, origin) => !origin.mounted);
    for (final entry in _scrollPositions.entries) {
      final box = entry.value.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          box.size.contains(box.globalToLocal(point)) &&
          entry.key.hasPixels &&
          entry.key.pixels > entry.key.minScrollExtent) {
        return false;
      }
    }
    return true;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (identical(event.original ?? event, _contentSignal)) {
      _contentSignal = null;
      return;
    }
    if (!widget.page ||
        event is! PointerScrollEvent ||
        event.scrollDelta.dy.abs() < event.scrollDelta.dx.abs() ||
        _exiting ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final spent = _wheelSpentUntil;
    if (spent != null && DateTime.now().isBefore(spent)) return;
    if (!_wheeling && (event.scrollDelta.dy >= 0 || !_atTop(event.position))) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!_wheeling) _start();
      _wheeling = true;
      _update(-event.scrollDelta.dy);
      _wheelEnd?.cancel();
      _wheelEnd = Timer(const Duration(milliseconds: 140), () {
        _wheeling = false;
        _wheelSpentUntil = DateTime.now().add(
          const Duration(milliseconds: 300),
        );
        _finish(0);
      });
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    if (_exiting || _pointer != null) return;
    _pointer = event.pointer;
    _pointerOwner = _DSheetPointerOwner.sheet;
    _velocity = VelocityTracker.withKind(PointerDeviceKind.trackpad)
      ..addPosition(event.timeStamp, Offset.zero);
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.pointer == _pointer) {
      _velocity?.addPosition(event.timeStamp, event.pan);
    }
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    if (event.pointer != _pointer) return;
    if (_scrollOrigin != null) {
      _finish(_velocity?.getVelocity().pixelsPerSecond.dy ?? 0);
    }
    _pointer = null;
    _pointerOwner = _DSheetPointerOwner.sheet;
    _velocity = null;
  }

  double get _offset {
    final dismissal = _dismissal;
    return dismissal == null
        ? _travel.value
        : _dismissOrigin +
              dismissal.distance *
                  (1 - widget.routeAnimation.value / dismissal.initialValue);
  }

  void _syncBackdrop() {
    widget.swipeProgress.value = (_offset / _swipeExtent).clamp(0, 1);
  }

  Simulation _beginDismissal(double velocity) {
    _travel.stop();
    _dismissOrigin = _travel.value;
    _dismissCurve = widget.popupCurve.value;
    final box = context.findRenderObject()! as RenderBox;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final top = box.localToGlobal(Offset.zero).dy + _dismissOrigin;
    _swipeExtent = math.max(1, viewportHeight - top + _dismissOrigin);
    return _dismissal = _DSheetDismissSimulation(
      math.max(1, viewportHeight - top),
      math.max(0, velocity),
      widget.routeAnimation.value,
    );
  }

  void _clearPendingSimulation() {
    if (_route?.reverseSimulationBuilder == _pendingSimulation) {
      _route?.reverseSimulationBuilder = null;
    }
    _pendingSimulation = null;
  }

  @override
  void initState() {
    super.initState();
    _travel.addListener(_syncBackdrop);
    widget.routeAnimation.addListener(_syncBackdrop);
    widget.routeAnimation.addStatusListener(_onRouteStatus);
  }

  @override
  void didUpdateWidget(_DSheetSwipeDismiss oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeAnimation == widget.routeAnimation) return;
    oldWidget.routeAnimation.removeListener(_syncBackdrop);
    oldWidget.routeAnimation.removeStatusListener(_onRouteStatus);
    widget.routeAnimation.addListener(_syncBackdrop);
    widget.routeAnimation.addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      // Controlled picker owners can forward a close over several frames.
      // Keep the drag offset when their route starts closing, even if the
      // fallback return animation has already been scheduled.
      _travel.stop();
    }
  }

  void _start() {
    if (_exiting ||
        _swipeIntercepted ||
        _pointerOwner == _DSheetPointerOwner.content) {
      return;
    }
    final box = context.findRenderObject()! as RenderBox;
    _swipeExtent = math.max(
      1,
      MediaQuery.sizeOf(context).height - box.localToGlobal(Offset.zero).dy,
    );
    _clearPendingSimulation();
    _travel.stop();
    _dragging = true;
  }

  void _update(double delta) {
    if (_exiting ||
        _swipeIntercepted ||
        _pointerOwner == _DSheetPointerOwner.content) {
      return;
    }
    _travel.value = math.max(0, _travel.value + delta);
    if (widget.onDismissRequested != null &&
        _travel.value >= _swipeExtent * _sheetDismissFraction) {
      _swipeIntercepted = true;
      _dragging = false;
      _scrollOrigin = null;
      _travel
        ..stop()
        ..value = 0;
      // Let the restored header lay out before its host opens an anchored menu.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDismissRequested?.call();
      });
    }
  }

  void _restore() {
    if (!mounted) return;
    final pending = _pendingSimulation;
    _travel
        .animateTo(
          0,
          duration: DMotion.duration(
            context,
            widget.page ? const Duration(milliseconds: 280) : DMotion.change,
          ),
          curve: Curves.easeOutCubic,
        )
        .whenCompleteOrCancel(() {
          if (mounted && _dismissal == null && _pendingSimulation == pending) {
            _clearPendingSimulation();
          }
        });
  }

  void _dismissRetained(double velocity) {
    _exiting = true;
    void complete() {
      if (!mounted) return;
      widget.onDismiss?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _exiting = false;
        _restore();
      });
    }

    if (MediaQuery.disableAnimationsOf(context)) {
      complete();
      return;
    }
    final box = context.findRenderObject()! as RenderBox;
    final distance = math.max(
      1.0,
      MediaQuery.sizeOf(context).height -
          box.localToGlobal(Offset.zero).dy -
          _travel.value,
    );
    unawaited(
      _travel
          .animateWith(
            _DSheetDismissSimulation(
              distance,
              math.max(0, velocity),
              _travel.value,
              endValue: _travel.value + distance,
              duration: widget.page ? .2 : .32,
            ),
          )
          .then<void>((_) => complete()),
    );
  }

  void _finish(double velocity, {bool cancelled = false}) {
    if (_swipeIntercepted) {
      _swipeIntercepted = false;
      return;
    }
    if (!_dragging) return;
    _dragging = false;
    _scrollOrigin = null;
    // Require a deliberate pull regardless of release speed. Measure against
    // the distance off-screen so opening the keyboard does not make the sheet
    // easier to dismiss; velocity only determines how an accepted exit moves.
    if (!cancelled &&
        (widget.page
            ? _travel.value > 120 || (_travel.value > 8 && velocity > 500)
            : _travel.value >= _swipeExtent * _sheetDismissFraction)) {
      if (widget.retained && widget.onDismiss != null) {
        _dismissRetained(velocity);
        return;
      }
      if (widget.retained) {
        _restore();
        return;
      }
      final route = ModalRoute.of(context);
      if (!MediaQuery.disableAnimationsOf(context) &&
          route is DOverlayRoute<dynamic, Object>) {
        _route = route;
        _pendingSimulation = () => _beginDismissal(velocity);
        route.reverseSimulationBuilder = _pendingSimulation;
      }
      widget.onDismiss?.call();
      // Controlled owners can decline the close request. Let their route
      // update before deciding whether the sheet needs to settle back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.routeAnimation.status != AnimationStatus.reverse &&
            widget.routeAnimation.status != AnimationStatus.dismissed) {
          _restore();
        }
      });
    } else {
      _restore();
    }
  }

  void _claimContentPointer(PointerEvent event) =>
      _claimPointer(event, _DSheetPointerOwner.content);

  void _claimHandlePointer(PointerEvent event) =>
      _claimPointer(event, _DSheetPointerOwner.handle);

  void _claimPointer(PointerEvent event, _DSheetPointerOwner owner) {
    if (_exiting ||
        _dragging ||
        (event is PointerPanZoomStartEvent && !widget.page) ||
        (_pointer != null && _pointer != event.pointer) ||
        (_pointer == event.pointer &&
            _pointerOwner == _DSheetPointerOwner.handle)) {
      return;
    }
    _pointer = event.pointer;
    _pointerOwner = owner;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(
        event.timeStamp,
        event is PointerPanZoomStartEvent ? Offset.zero : event.position,
      );
  }

  void _claimContentSignal(PointerSignalEvent event) {
    if (widget.page && !_wheeling && event is PointerScrollEvent) {
      _contentSignal = event.original ?? event;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_exiting || _pointer != null || event.kind != PointerDeviceKind.touch) {
      return;
    }
    _pointer = event.pointer;
    _pointerOwner = _DSheetPointerOwner.sheet;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _pointer) {
      _velocity?.addPosition(event.timeStamp, event.position);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    if (_scrollOrigin != null || _swipeIntercepted) {
      _finish(_velocity?.getVelocity().pixelsPerSecond.dy ?? 0);
    }
    _pointer = null;
    _pointerOwner = _DSheetPointerOwner.sheet;
    _velocity = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _finish(0, cancelled: true);
    _pointer = null;
    _pointerOwner = _DSheetPointerOwner.sheet;
    _velocity = null;
  }

  bool _onScroll(ScrollNotification notification) {
    _rememberScroll(notification.context);
    if (_exiting ||
        _swipeIntercepted ||
        _pointer == null ||
        _pointerOwner == _DSheetPointerOwner.content ||
        notification.metrics.axisDirection != AxisDirection.down ||
        (_scrollOrigin != null && _scrollOrigin != notification.context)) {
      return false;
    }
    final details = switch (notification) {
      OverscrollNotification(:final dragDetails) => dragDetails,
      ScrollUpdateNotification(:final dragDetails) => dragDetails,
      _ => null,
    };
    if (details == null) return false;
    if (_scrollOrigin != null) {
      // Once scrolling reaches an edge, track the finger like a header drag.
      // Applying bouncing-scroll resistance here would swallow the handoff.
      _update(details.delta.dy);
      return false;
    }

    double delta = 0;
    if (notification is OverscrollNotification) {
      delta = notification.overscroll;
    } else if (notification is ScrollUpdateNotification) {
      // Bouncing physics move outside the range instead of reporting an
      // OverscrollNotification. Transfer only movement beyond the edge.
      final pixels = notification.metrics.pixels;
      final minimum = notification.metrics.minScrollExtent;
      final previous = pixels - (notification.scrollDelta ?? 0);
      delta = math.max(0, minimum - previous) - math.max(0, minimum - pixels);
    }
    final atTop =
        notification.metrics.pixels <= notification.metrics.minScrollExtent;
    if (atTop && delta < 0 && details.delta.dy > 0) {
      if (!_dragging) _start();
      _scrollOrigin = notification.context;
      _update(delta.abs());
    }
    return false;
  }

  @override
  void dispose() {
    _wheelEnd?.cancel();
    _clearPendingSimulation();
    widget.routeAnimation.removeListener(_syncBackdrop);
    widget.routeAnimation.removeStatusListener(_onRouteStatus);
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_travel, widget.routeAnimation]),
    builder: (context, child) {
      final dismissal = _dismissal;
      return Transform.translate(
        offset: Offset(0, _offset),
        child: _DSheetMotion(
          curve: dismissal == null
              ? widget.popupCurve
              : AlwaysStoppedAnimation(_dismissCurve),
          beginOffset: const Offset(0, 40),
          scale: widget.scale,
          child: child!,
        ),
      );
    },
    child: Listener(
      onPointerSignal: widget.page ? _onPointerSignal : null,
      onPointerPanZoomStart: widget.page ? _onPanZoomStart : null,
      onPointerPanZoomUpdate: widget.page ? _onPanZoomUpdate : null,
      onPointerPanZoomEnd: widget.page ? _onPanZoomEnd : null,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        supportedDevices: const {PointerDeviceKind.touch},
        onVerticalDragStart: (_) => _start(),
        onVerticalDragUpdate: (details) => _update(details.delta.dy),
        onVerticalDragEnd: (details) => _finish(details.primaryVelocity ?? 0),
        onVerticalDragCancel: () => _finish(0, cancelled: true),
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _rememberScroll(notification.context);
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: _DSheetSwipeScope(
              swipe: this,
              child: SheetContentGestureScope(
                onPointer: _claimContentPointer,
                onSignal: _claimContentSignal,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
    this.variant = DSheetVariant.standard,
    this.sizeToContent = true,
    this.contentLoading = false,
    this.showCloseButton = true,

    this.semanticLabel,
    this.backgroundColor,
    this.headerImage,
    this.sidePanelMaxWidth = 384,
    this.sidePanelWidth,
    this.inset = false,

    this.scrollWholeSheet,
    this.topBottomMaxHeightFactor,
    this.fillAvailableHeight = false,
    this.extendBehindKeyboard = false,
  }) : assert(!extendBehindKeyboard || fillAvailableHeight),

       assert(sidePanelMaxWidth > 0),
       assert(sidePanelWidth == null || sidePanelWidth > 0),
       assert(
         topBottomMaxHeightFactor == null ||
             (topBottomMaxHeightFactor > 0 && topBottomMaxHeightFactor <= 1),
       );

  final List<Widget> children;
  final DSheetVariant variant;

  /// Whether an adaptive menu follows the height of its content.
  ///
  /// False reserves a 55% opening viewport, including floating clearance,
  /// across loading and result changes. Pulling upward expands it; a visible
  /// keyboard uses the available viewport. Other sheet variants are unchanged.
  final bool sizeToContent;

  /// Defers an adaptive menu's short-content margins until loading finishes.
  ///
  /// Existing margins remain until dismissal. This does not render a loading
  /// indicator or affect other sheet variants.
  final bool contentLoading;
  final DSheetSide side;
  final bool showCloseButton;

  String get closeSemanticLabel => appL10n.close;
  final String? semanticLabel;

  /// The surface fill override.
  ///
  /// Defaults to opaque [DTokens.background] for full-height sheets and
  /// [DTokens.surface] otherwise.
  final Color? backgroundColor;

  /// A menu banner behind its identity row and overlaid grab handle.
  /// The Native wash preserves legibility over light and dark artwork.
  final ImageProvider<Object>? headerImage;

  final double sidePanelMaxWidth;

  /// An exact side-panel width, clamped to [sidePanelMaxWidth] and the viewport.
  ///
  /// Null preserves Sheet's responsive 75% width and 384px desktop cap.
  final double? sidePanelWidth;

  /// Floats the surface inside the viewport with shared spacing and rounded
  /// corners, above the bottom safe area. The safe inset is consumed outside
  /// the surface so its content does not repeat that padding. The default
  /// retains the reference's fixed-edge presentation.
  final bool inset;

  /// Overrides automatic whole-surface scrolling at large text sizes.
  ///
  /// Null preserves the default. Set false only when a composed child owns a
  /// bounded scroll region while its surrounding header and footer stay fixed.
  final bool? scrollWholeSheet;

  /// Optional cap used by long top and bottom compositions.
  final double? topBottomMaxHeightFactor;

  /// Whether the sheet fills the viewport above the keyboard.
  ///
  /// The top gap is at least 11% of the viewport and 24px below the safe area.
  /// [extendBehindKeyboard] instead fills to the bottom of the viewport with
  /// an 8px gap below the top safe area.
  final bool fillAvailableHeight;

  /// Whether a full-height sheet paints behind the keyboard.
  ///
  /// The live bottom view inset remains available to the content, which must
  /// keep controls and scroll reveal bounds above it. Bottom safe-area padding
  /// is also content-owned. An edge-to-edge sheet has rounded top corners.
  final bool extendBehindKeyboard;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final inset = _DSheetSideScope.insetOf(context) ?? this.inset;
    final fillAvailableHeight =
        _DSheetSideScope.fillsAvailableHeightOf(context) ??
        this.fillAvailableHeight;
    final extendBehindKeyboard =
        _DSheetSideScope.extendsBehindKeyboardOf(context) ??
        this.extendBehindKeyboard;
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
    final overArtwork = headerImage != null;
    final page = variant == DSheetVariant.page;
    final menu =
        variant == DSheetVariant.menu || variant == DSheetVariant.adaptiveMenu;
    final handle = Padding(
      padding: EdgeInsets.only(top: page ? 7 : 8, bottom: page ? 9 : 10),
      child: Center(
        child: DSheetDragRegion(
          child: ExcludeSemantics(
            child: DecoratedBox(
              key: const ValueKey('sheet-drag-handle'),
              decoration: BoxDecoration(
                color: overArtwork
                    ? Colors.white.withValues(alpha: .9)
                    : Color.lerp(
                        tokens.background,
                        tokens.foreground,
                        .35,
                      )!.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [],
              ),
              child: const SizedBox(width: 36, height: 5),
            ),
          ),
        ),
      ),
    );
    if (page) {
      final pulled =
          context
              .dependOnInheritedWidgetOfExactType<_DSheetPagePullScope>()
              ?.pulled ??
          false;
      final color = backgroundColor ?? tokens.panelBackground;
      return Semantics(
        container: true,
        explicitChildNodes: true,
        scopesRoute: true,
        label: semanticLabel,
        child: _DSheetPageCard(
          color: pulled ? color.withValues(alpha: 1) : color,
          handle: handle,
          children: children,
        ),
      );
    }
    final parts = <Widget>[if (menu && !overArtwork) handle];
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

    // A sheet to write on runs to the screen's foot with no edge drawn round
    // it; its round and the shadow it casts up are enough.
    final writing = menu && extendBehindKeyboard;
    final edgeBorder = BorderSide(color: tokens.border);
    final border = writing
        ? null
        : inset
        ? Border.all(color: tokens.border)
        : switch (resolved) {
            DSheetSide.center => Border.all(color: tokens.border),
            DSheetSide.top => Border(bottom: edgeBorder),
            DSheetSide.right => Border(left: edgeBorder),
            DSheetSide.bottom when menu => Border(
              top: edgeBorder,
              left: edgeBorder,
              right: edgeBorder,
            ),
            DSheetSide.bottom => Border(top: edgeBorder),
            DSheetSide.left => Border(right: edgeBorder),
            _ => throw StateError('Sheet side was not resolved.'),
          };
    final menuInsetProgress = context
        .dependOnInheritedWidgetOfExactType<_DSheetSideScope>()
        ?.menuInsetProgress;
    final radius = menu
        ? BorderRadius.vertical(
            top: const Radius.circular(22),
            bottom: Radius.circular(24 * (menuInsetProgress ?? 1)),
          )
        : inset
        ? BorderRadius.circular(DRadius.panel)
        : extendBehindKeyboard
        ? const BorderRadius.vertical(top: Radius.circular(DRadius.panel * 2))
        : BorderRadius.zero;
    final surfaceColor =
        backgroundColor ??
        (menu
            ? tokens.panelBackground
            : fillAvailableHeight
            ? tokens.background.withValues(alpha: 1)
            : tokens.surface);
    final edges = menu
        ? DSurfaceEdges.resolve(
            context,
            writing ? DSurfaceDepth.fullSheet : DSurfaceDepth.menu,
          )
        : null;
    Widget surface = CustomPaint(
      painter: edges?.castPainter(radius),
      // Over the content, as the border is: what is at a sheet's top edge is
      // its handle, on the sheet's own fill. A banner would cover it.
      foregroundPainter: overArtwork
          ? null
          : edges?.insetPainter(
              radius,
              border: border?.dimensions as EdgeInsets? ?? EdgeInsets.zero,
            ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: border, borderRadius: radius),
        child: Material(
          animationDuration: Duration.zero,
          borderRadius: radius,
          clipBehavior: inset || extendBehindKeyboard || menu
              ? Clip.antiAlias
              : Clip.none,
          color: surfaceColor,
          textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: DiscourseTypography.sm,
            height: 20 / 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: tokens.foreground,
          ),
          child: SafeArea(
            bottom: !extendBehindKeyboard,
            minimum: EdgeInsets.only(
              bottom: extendBehindKeyboard
                  ? 0
                  : MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Stack(
              children: [
                if (headerImage != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 132,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image(
                              image: headerImage!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    surfaceColor.withValues(alpha: .45),
                                    surfaceColor.withValues(alpha: .84),
                                    surfaceColor,
                                  ],
                                  stops: const [0, .55, 1],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
                if (menu && overArtwork)
                  Positioned(top: 0, left: 0, right: 0, child: handle),
                if (showCloseButton)
                  Positioned(
                    top: DSpacing.md,
                    right: DSpacing.md,
                    child: (DSheetClose<void>(
                      builder: (context, close) => DButton.iconOnly(
                        onPressed: close,
                        size: DButtonSize.small,
                        variant: DButtonVariant.ghost,
                        icon: const _DSheetCloseIcon(),
                        tooltip: closeSemanticLabel,
                        semanticLabel: closeSemanticLabel,
                      ),
                    )),
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

    this.padding = const EdgeInsets.symmetric(horizontal: DSpacing.lg),
  });

  final Widget child;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: null,
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
  const DSheetClose({super.key, required this.builder});

  final DSheetCloseBuilder builder;

  @override
  Widget build(BuildContext context) =>
      DDialogClose<T>(result: null, builder: builder);
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
    Widget Function(BuildContext context, DSheetController<T> controller);

/// Opens a route-owned Sheet and returns its typed result.
Future<T?> showDSheet<T>({
  required BuildContext context,
  required DSheetContentBuilder<T> builder,
  DSheetSide side = DSheetSide.right,

  bool inset = false,
  DSheetVariant variant = DSheetVariant.standard,
  bool sizeToContent = true,
  bool contentLoading = false,

  bool fillAvailableHeight = false,

  bool useRootNavigator = false,
  bool dismissOnSwipe = true,
  bool Function()? canDismiss,

  /// Caps and centers fixed-edge top and bottom surfaces.
  double? topBottomMaxWidth,

  String? barrierLabel,

  FocusNode? initialFocusNode,
  FocusNode? finalFocusNode,
}) {
  assert(topBottomMaxWidth == null || topBottomMaxWidth > 0);
  return showDDialog<T>(
    context: context,
    builder: builder,
    useRootNavigator: useRootNavigator,
    modal: true,
    dismissOnBarrier: true,
    dismissOnEscape: true,
    canDismiss: canDismiss,
    barrierLabel: barrierLabel ?? appL10n.dismissSheet,
    routeSettings: null,
    initialFocusNode: initialFocusNode,
    finalFocusNode: finalFocusNode,
    presentationBuilder: (context, presentation) => _sheetPresentation(
      context,
      presentation,
      side,
      384,
      null,
      inset,
      false,
      fillAvailableHeight,
      false,
      dismissOnSwipe,
      variant: variant,
      sizeToContent: sizeToContent,
      contentLoading: contentLoading,
      topBottomMaxWidth: topBottomMaxWidth,
    ),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
  );
}
