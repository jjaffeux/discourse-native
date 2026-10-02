import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/tokens.dart';

/// Interactive edge swipes over a single live history page.
///
/// Give each visit a stable [entry] identity and change [history] when its owner
/// or journey changes. Adjacent identities select visual previews; callbacks
/// change the actual history only after a committed swipe finishes. Short drags
/// spring back without invoking a callback. Null callbacks disable that edge.
/// A shallow parallax and soft edge shadow separate the pages during a drag.
/// Tab switches use a short directional slide and crossfade.
///
/// History previews are in-memory snapshots. Up to eight recently visited
/// pages are retained, at most one million pixels each.
/// Unvisited/evicted pages and platform views use the background as a fallback.
/// Supply [previousPreview] or [nextPreview] for an adjacent navigation surface
/// that must be ready on its first reveal. These remain mounted offstage, with
/// focus, semantics and interaction excluded until they become the real page.
/// Theme, viewport width, history and app lifecycle changes discard snapshots.
/// Reduced motion keeps the page stationary while preserving the gestures.
class DHistoryTransition extends StatefulWidget {
  const DHistoryTransition({
    super.key,
    required this.history,
    required this.entry,
    required this.child,
    this.previousEntry,
    this.nextEntry,
    this.previousPreview,
    this.nextPreview,
    this.onBack,
    this.onForward,
    this.tabIndex,
    this.tabOwner,
    this.frameBuilder,
  }) : assert(tabIndex == null || tabOwner != null);

  final Object history;
  final Object entry;
  final Object? previousEntry;
  final Object? nextEntry;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final Widget child;

  /// Places the animated page within stationary navigation chrome.
  ///
  /// The whole returned frame accepts edge swipes, including its padding and
  /// chrome. Only the supplied page moves and is captured for history previews.
  /// Insert it once with bounded width and height. Without a builder it fills the
  /// gesture surface.
  final Widget Function(BuildContext context, Widget page)? frameBuilder;

  /// A live previous navigation surface, kept ready before the first swipe.
  ///
  /// Do not supply a second renderer for a history page; its snapshot is used
  /// automatically. A [GlobalKey] can preserve it when it becomes [child].
  final Widget? previousPreview;

  /// A live next navigation surface, kept ready before the first swipe.
  ///
  /// Like [previousPreview], this remains inert and mounted offstage until a
  /// swipe reveals it. Use a snapshot for history pages with a live renderer.
  final Widget? nextPreview;

  /// The selected tab's visual order. A changed index slides and fades pages in
  /// that direction, mirrored in RTL, even when [history] resets for a new tab.
  /// Only the destination is live; the outgoing page uses a bounded snapshot.
  final int? tabIndex;

  /// Account/site identity for tab transitions. Changing owners clears images
  /// immediately and never animates the previous owner's content.
  final Object? tabOwner;

  @override
  State<DHistoryTransition> createState() => _DHistoryTransitionState();
}

class _DHistoryTransitionState extends State<DHistoryTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _edgeWidth = 48.0;
  static const _commitDistance = 64.0;
  static const _parallax = .08;
  static const _tabTravel = 24.0;

  final _boundary = GlobalKey();
  final _previews = <Object, ui.Image>{};
  final _pointers = <int>{};
  late final _progress = AnimationController(vsync: this);
  ui.Image? _preview;
  Object? _environment;
  Object? _committedEntry;
  Size _size = Size.zero;
  double _gestureWidth = 0;
  bool _back = false;
  bool _dragging = false;
  bool _settling = false;
  bool _switchingTab = false;
  double _tabSign = 1;
  double _distance = 0;
  int _generation = 0;

  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;
  bool get _rtl => Directionality.of(context) == TextDirection.rtl;
  double get _sign => _back != _rtl ? 1 : -1;
  Object? get _target => _back ? widget.previousEntry : widget.nextEntry;
  VoidCallback? get _navigate => _back ? widget.onBack : widget.onForward;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final environment = (
      Theme.of(context),
      MediaQuery.of(context),
      Directionality.of(context),
    );
    if (_environment != environment) {
      _environment = environment;
      _clear();
    }
    if (!_routeIsCurrent) _resetGesture();
  }

  @override
  void didUpdateWidget(DHistoryTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final committed = _committedEntry == widget.entry;
    _committedEntry = null;
    if (oldWidget.tabOwner != widget.tabOwner) {
      _clear();
    } else if (oldWidget.tabIndex != null &&
        widget.tabIndex != null &&
        oldWidget.tabIndex != widget.tabIndex &&
        !committed &&
        !MediaQuery.disableAnimationsOf(context) &&
        _routeIsCurrent) {
      final boundary = _boundary.currentContext?.findRenderObject();
      final image = boundary is _HistoryRepaintBoundary
          ? boundary.snapshot(MediaQuery.devicePixelRatioOf(context))
          : null;
      if (oldWidget.history == widget.history) {
        _resetGesture();
        if (image != null) _remember(oldWidget.entry, image.clone());
      } else {
        _clear();
      }
      _preview = image;
      _tabSign =
          (widget.tabIndex! > oldWidget.tabIndex! ? 1 : -1) *
          (_rtl ? -1.0 : 1.0);
      _switchingTab = true;
      unawaited(_animateTab());
    } else if (oldWidget.history != widget.history) {
      _clear();
    } else if (oldWidget.entry != widget.entry) {
      // The descendant still contains the outgoing page's last painted frame.
      // Capture it before rebuilding that one live renderer for the new entry.
      final boundary = _boundary.currentContext?.findRenderObject();
      if (boundary is _HistoryRepaintBoundary &&
          !MediaQuery.disableAnimationsOf(context)) {
        final image = boundary.snapshot(MediaQuery.devicePixelRatioOf(context));
        if (image != null) {
          _remember(oldWidget.entry, image);
        }
      }
      _resetGesture();
    } else if ((_dragging || _settling) &&
        (_navigate == null ||
            _target !=
                (_back ? oldWidget.previousEntry : oldWidget.nextEntry))) {
      _resetGesture();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) setState(_clear);
  }

  @override
  void didHaveMemoryPressure() => setState(_clear);

  void _resetGesture() {
    _generation++;
    _dragging = false;
    _settling = false;
    _switchingTab = false;
    _distance = 0;
    _progress.stop();
    _progress.value = 0;
    final preview = _preview;
    _preview = null;
    // A RawImage from this frame may still own the old handle until rebuild.
    if (preview != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => preview.dispose());
    }
  }

  void _clear() {
    _committedEntry = null;
    _resetGesture();
    _pointers.clear();
    for (final image in _previews.values) {
      image.dispose();
    }
    _previews.clear();
  }

  void _remember(Object entry, ui.Image image) {
    _previews.remove(entry)?.dispose();
    _previews[entry] = image;
    while (_previews.length > 8) {
      _previews.remove(_previews.keys.first)!.dispose();
    }
  }

  bool _allowsPointer(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch ||
        _pointers.length > 1 ||
        _dragging ||
        _settling ||
        _switchingTab ||
        !_routeIsCurrent ||
        _size.isEmpty ||
        _gestureWidth <= _edgeWidth * 2) {
      return false;
    }
    final x = event.localPosition.dx;
    if (x > _edgeWidth && x < _gestureWidth - _edgeWidth) return false;
    final back = _rtl ? x >= _gestureWidth - _edgeWidth : x <= _edgeWidth;
    return back
        ? widget.previousEntry != null && widget.onBack != null
        : widget.nextEntry != null && widget.onForward != null;
  }

  void _start(DragStartDetails details) {
    if (_pointers.length != 1 || !_routeIsCurrent) return;
    setState(() {
      _back = _rtl
          ? details.localPosition.dx >= _gestureWidth - _edgeWidth
          : details.localPosition.dx <= _edgeWidth;
      _dragging = true;
      _distance = 0;
      _preview = _previews[_target]?.clone();
    });
  }

  void _update(DragUpdateDetails details) {
    if (!_dragging) return;
    if (!_routeIsCurrent || _pointers.length > 1) {
      unawaited(_settle(false));
      return;
    }
    _distance = (_distance + details.primaryDelta! * _sign).clamp(
      0,
      _size.width,
    );
    _progress.value = _distance / _size.width;
  }

  void _end(DragEndDetails details) {
    if (!_dragging) return;
    final velocity = (details.primaryVelocity ?? 0) * _sign;
    final commit = velocity.abs() >= 650
        ? velocity > 0 && _progress.value > 0
        : _distance >= _commitDistance;
    unawaited(_settle(commit, velocity: velocity));
  }

  Future<void> _settle(bool commit, {double velocity = 0}) async {
    if (!_dragging) return;
    _dragging = false;
    _settling = true;
    final generation = ++_generation;
    final remaining = commit ? 1 - _progress.value : _progress.value;
    final milliseconds = velocity > 0 && commit
        ? (remaining * _size.width / velocity * 1000).clamp(
            DMotion.close.inMilliseconds,
            DMotion.change.inMilliseconds,
          )
        : (DMotion.change.inMilliseconds * math.sqrt(remaining)).clamp(
            DMotion.close.inMilliseconds,
            DMotion.change.inMilliseconds,
          );
    try {
      await _progress
          .animateTo(
            commit ? 1 : 0,
            duration: DMotion.duration(
              context,
              Duration(milliseconds: milliseconds.round()),
            ),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _generation) return;
    final navigate = commit && _routeIsCurrent ? _navigate : null;
    // A sidebar changes tabIndex as well as entry. The drag has already carried
    // it into place, so its committed update must not start another animation.
    _committedEntry = navigate != null ? _target : null;
    setState(_resetGesture);
    navigate?.call();
  }

  Future<void> _animateTab() async {
    final generation = _generation;
    try {
      await _progress
          .animateTo(
            1,
            duration: DMotion.duration(context, DMotion.change),
            curve: Curves.easeInOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted && generation == _generation) setState(_resetGesture);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _gestureWidth = constraints.maxWidth;
      final page = _buildPage(context);
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _pointers.add(event.pointer);
          if (_pointers.length > 1) unawaited(_settle(false));
        },
        onPointerUp: (event) => _pointers.remove(event.pointer),
        onPointerCancel: (event) {
          _pointers.remove(event.pointer);
          unawaited(_settle(false));
        },
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            _HistoryEdgeRecognizer:
                GestureRecognizerFactoryWithHandlers<_HistoryEdgeRecognizer>(
                  _HistoryEdgeRecognizer.new,
                  (recognizer) => recognizer
                    ..allowsPointer = _allowsPointer
                    ..dragStartBehavior = DragStartBehavior.down
                    ..onStart = _start
                    ..onUpdate = _update
                    ..onEnd = _end
                    ..onCancel = () => unawaited(_settle(false)),
                ),
          },
          child: widget.frameBuilder?.call(context, page) ?? page,
        ),
      );
    },
  );

  Widget _buildPage(BuildContext context) {
    final tokens = DTokens.of(context);
    final background = tokens.background;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_size != constraints.biggest) {
          // The dock changes the viewport's height when navigation opens.
          // Keep same-width previews at their original aspect ratio so closing
          // navigation can reveal the page without stretching its text.
          final widthChanged = _size.width != constraints.maxWidth;
          _size = constraints.biggest;
          if (widthChanged) {
            _clear();
          } else if (_dragging || _settling) {
            _resetGesture();
          }
        }
        return ClipRect(
          child: AnimatedBuilder(
            animation: _progress,
            child: _HistoryBoundary(key: _boundary, child: widget.child),
            builder: (context, child) {
              final switching = _switchingTab && !reducedMotion;
              final p = reducedMotion ? 0.0 : _progress.value;
              final active = !switching && p > 0;
              final dim = BoxDecoration(
                color: tokens.colors.scrim.withValues(
                  alpha: active ? .06 * (_back ? 1 - p : p) : 0,
                ),
              );
              final elevation = BoxDecoration(
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: tokens.colors.shadow.withValues(alpha: .12),
                          blurRadius: 12,
                          offset: Offset(_rtl ? 3 : -3, 0),
                        ),
                      ]
                    : null,
              );
              final preview = ExcludeSemantics(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: background,
                    child: _preview == null
                        ? null
                        : RawImage(
                            image: _preview,
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topCenter,
                          ),
                  ),
                ),
              );
              Widget previewLayer(Widget preview, {required bool back}) =>
                  Offstage(
                    key: ValueKey(
                      back
                          ? 'history-previous-preview'
                          : 'history-next-preview',
                    ),
                    offstage: !active || _back != back,
                    child: Transform.translate(
                      offset: Offset(
                        back
                            ? -_sign * _size.width * _parallax * (1 - p)
                            : -_sign * _size.width * (1 - p),
                        0,
                      ),
                      child: DecoratedBox(
                        decoration: back ? dim : elevation,
                        position: back
                            ? DecorationPosition.foreground
                            : DecorationPosition.background,
                        child: ExcludeSemantics(
                          child: IgnorePointer(
                            child: ExcludeFocus(
                              child: TickerMode(
                                enabled: active && _back == back,
                                child: preview,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.previousPreview case final live?)
                    previewLayer(live, back: true)
                  else if (active && _back)
                    previewLayer(preview, back: true),
                  if (switching)
                    Transform.translate(
                      key: const ValueKey('history-outgoing-tab'),
                      offset: Offset(-_tabSign * _tabTravel * p, 0),
                      child: ExcludeSemantics(
                        child: Opacity(
                          opacity: 1 - p,
                          child: RawImage(
                            image: _preview,
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                    ),
                  Transform.translate(
                    key: ValueKey(
                      switching ? 'history-incoming-tab' : 'history-live-page',
                    ),
                    offset: Offset(
                      switching
                          ? _tabSign * _tabTravel * (1 - p)
                          : _sign * _size.width * p * (_back ? 1 : _parallax),
                      0,
                    ),
                    // Keep depth effects outside the capture boundary so
                    // revisiting a page never reuses a darkened snapshot.
                    child: DecoratedBox(
                      decoration: _back ? elevation : dim,
                      position: _back
                          ? DecorationPosition.background
                          : DecorationPosition.foreground,
                      child: IgnorePointer(
                        ignoring: _dragging || _settling || switching,
                        child: Opacity(
                          opacity: switching ? p : 1,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                  if (widget.nextPreview case final live?)
                    previewLayer(live, back: false)
                  else if (active && !_back)
                    previewLayer(preview, back: false),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _HistoryEdgeRecognizer extends HorizontalDragGestureRecognizer {
  bool Function(PointerDownEvent)? allowsPointer;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      event is PointerDownEvent &&
      (allowsPointer?.call(event) ?? false) &&
      super.isPointerAllowed(event);
}

class _HistoryBoundary extends SingleChildRenderObjectWidget {
  const _HistoryBoundary({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _HistoryRepaintBoundary();
}

class _HistoryRepaintBoundary extends RenderRepaintBoundary {
  Size? _paintedSize;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _paintedSize = size;
  }

  // Read the last composited frame even if this boundary is already dirty.
  // The outgoing subtree has not been rebuilt yet. Rasterization is deferred
  // by toImageSync, so navigation does not wait for a GPU readback.
  ui.Image? snapshot(double devicePixelRatio) {
    final painted = _paintedSize;
    final paintedLayer = layer;
    if (painted == null || painted.isEmpty || paintedLayer is! OffsetLayer) {
      return null;
    }
    final ratio = math.min(
      math.min(devicePixelRatio, 1.5),
      math.sqrt(1000000 / (painted.width * painted.height)),
    );
    return paintedLayer.toImageSync(Offset.zero & painted, pixelRatio: ratio);
  }
}
