import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/tokens.dart';

/// A tab among ordered tabs: which one, and where it stands among them.
typedef DHistoryTab = ({Object id, int index});

/// Interactive edge swipes over a single live history page.
///
/// Give each visit a stable [entry] identity and change [history] when its owner
/// or journey changes. Adjacent identities select visual previews; callbacks
/// change the actual history only after a committed swipe finishes. Short drags
/// spring back without invoking a callback. Null callbacks disable that edge.
/// The incoming page grows from 94% to full size with the swipe. Shallow
/// parallax separates the pages during a drag. Background
/// pages stay inside the viewport, shrinking as a forward page covers them.
/// The background page lightens as it is revealed and darkens as it is covered.
/// Tab switches slide directionally and crossfade the pages.
///
/// History previews are in-memory snapshots. Up to eight recently visited
/// pages are retained, at most one million pixels each.
/// Unvisited/evicted pages and platform views use the background as a fallback.
/// Supply [previousPreview] or [nextPreview] for an adjacent navigation surface
/// that must be ready on its first reveal. These remain mounted offstage, with
/// focus, semantics and interaction excluded until they become the real page.
/// Theme, viewport width, history and app lifecycle changes discard snapshots.
/// Reduced motion keeps the page stationary while preserving the gestures.
/// Departures are still captured for descendant reading-sheet underlays.
/// Keyboard insets do not invalidate those departure snapshots.
class DHistoryTransition extends StatefulWidget {
  const DHistoryTransition({
    super.key,
    required this.history,
    required this.entry,
    required this.child,
    this.previousEntry,
    this.nextEntry,
    this.previousPreview,

    this.onBack,
    this.onForward,
    this.tab,
    this.tabOwner,
    this.frameBuilder,
  }) : assert(tab == null || tabOwner != null);

  /// The previous visit's inert snapshot for a descendant reading sheet.
  ///
  /// Returns `null` when that visit has no retained image. The image stays
  /// aligned with this transition's captured page, including any padding
  /// between the capture boundary and the sheet. It retains its aspect ratio
  /// when the available height changes. Native owns the image lifetime.
  static Widget? previousPageUnderlayOf(BuildContext context) {
    final image = context
        .dependOnInheritedWidgetOfExactType<_HistoryPageScope>()
        ?.previousImage;
    return image == null
        ? null
        : ExcludeSemantics(
            child: ExcludeFocus(
              child: IgnorePointer(
                child: _HistorySnapshotUnderlay(image: image),
              ),
            ),
          );
  }

  /// Whether a descendant page should play its own entrance.
  /// Returning to an earlier visit, switching tabs, and committing an edge
  /// swipe already reveal that page without another entrance transition.
  static bool shouldAnimatePageEntranceOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_HistoryPageScope>()
          ?.animatePageEntrance ??
      true;

  /// The destination and progress of an edge swipe, including its settle.
  ///
  /// Descendants of [frameBuilder] can use this to move navigation chrome with
  /// the page. Returns null at rest, during tab switches, and in reduced motion.
  static ({Object entry, double progress})? swipeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HistorySwipeScope>()?.swipe;

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

  /// The selected tab and its visual order. Another tab slides and fades the
  /// pages towards its index, mirrored in RTL, even when [history] resets for
  /// it. Only the destination is live; the outgoing page uses a bounded
  /// snapshot. The same tab at another index, as when tabs are reordered,
  /// moves nothing.
  final DHistoryTab? tab;

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
  static const _previewScale = .94;
  // Match the horizontal inset from centered scaling, so the background's
  // leading edge stays visible instead of sliding outside the viewport.
  static const _parallax = (1 - _previewScale) / 2;
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
  bool _animatePageEntrance = true;
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
    final media = MediaQuery.of(context);
    final environment = (
      Theme.of(context),
      media.copyWith(
        viewInsets: EdgeInsets.zero,
        padding: media.padding.copyWith(bottom: media.viewPadding.bottom),
      ),
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
    if (oldWidget.entry != widget.entry ||
        oldWidget.history != widget.history) {
      _animatePageEntrance =
          !committed &&
          widget.entry != oldWidget.previousEntry &&
          oldWidget.history == widget.history &&
          oldWidget.tab?.id == widget.tab?.id;
    }
    if (oldWidget.tabOwner != widget.tabOwner) {
      _clear();
    } else if ((oldWidget.tab, widget.tab) case (final was?, final now?)
        when was.id != now.id &&
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
      _tabSign = (now.index > was.index ? 1 : -1) * (_rtl ? -1.0 : 1.0);
      _switchingTab = true;
      unawaited(_animateTab());
    } else if (oldWidget.history != widget.history) {
      _clear();
    } else if (oldWidget.entry != widget.entry) {
      // The descendant still contains the outgoing page's last painted frame.
      // Capture it before rebuilding that one live renderer for the new entry.
      final boundary = _boundary.currentContext?.findRenderObject();
      if (boundary is _HistoryRepaintBoundary) {
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
    if (_progress.value != 0) _progress.value = 0;
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
          child: widget.frameBuilder == null
              ? page
              : AnimatedBuilder(
                  animation: _progress,
                  builder: (context, child) => _HistorySwipeScope(
                    swipe:
                        !_switchingTab &&
                            (_dragging || _settling) &&
                            !MediaQuery.disableAnimationsOf(context)
                        ? (entry: _target!, progress: _progress.value)
                        : null,
                    child: child!,
                  ),
                  child: Builder(
                    builder: (context) => widget.frameBuilder!(context, page),
                  ),
                ),
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
            child: _HistoryPageScope(
              previousImage: _previews[widget.previousEntry],
              animatePageEntrance: _animatePageEntrance,
              child: _HistoryBoundary(key: _boundary, child: widget.child),
            ),
            builder: (context, child) {
              final switching = _switchingTab && !reducedMotion;
              final p = reducedMotion ? 0.0 : _progress.value;
              final active = !switching && p > 0;
              // Tint only painted pixels. A rectangular scrim would also
              // darken transparent page gutters and rounded corners.
              final dim = ColorFilter.mode(
                tokens.colors.scrim.withValues(
                  alpha: active ? .40 * (_back ? 1 - p : p) : 0,
                ),
                BlendMode.srcATop,
              );
              const clear = ColorFilter.mode(
                Colors.transparent,
                BlendMode.srcATop,
              );
              const elevation = BoxDecoration(boxShadow: []);
              final preview = ExcludeSemantics(
                child: IgnorePointer(
                  child: _preview == null
                      ? ColoredBox(color: background)
                      : RawImage(
                          image: _preview,
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.topCenter,
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
                      child: Transform.scale(
                        scale: reducedMotion
                            ? 1
                            : _previewScale + (1 - _previewScale) * p,
                        child: DecoratedBox(
                          decoration: back ? const BoxDecoration() : elevation,
                          child: ColorFiltered(
                            colorFilter: back ? dim : clear,
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
                    child: Transform.scale(
                      scale: switching || _back
                          ? 1
                          : 1 - (1 - _previewScale) * p,
                      child: DecoratedBox(
                        decoration: _back ? elevation : const BoxDecoration(),
                        child: ColorFiltered(
                          colorFilter: _back ? clear : dim,
                          child: IgnorePointer(
                            ignoring: _dragging || _settling || switching,
                            child: Opacity(
                              opacity: switching ? p : 1,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (active && !_back) previewLayer(preview, back: false),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _HistorySwipeScope extends InheritedWidget {
  const _HistorySwipeScope({required this.swipe, required super.child});

  final ({Object entry, double progress})? swipe;

  @override
  bool updateShouldNotify(_HistorySwipeScope oldWidget) =>
      swipe != oldWidget.swipe;
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

class _HistoryPageScope extends InheritedWidget {
  const _HistoryPageScope({
    required this.previousImage,
    required this.animatePageEntrance,
    required super.child,
  });

  final ui.Image? previousImage;
  final bool animatePageEntrance;

  @override
  bool updateShouldNotify(_HistoryPageScope oldWidget) =>
      previousImage != oldWidget.previousImage ||
      animatePageEntrance != oldWidget.animatePageEntrance;
}

class _HistorySnapshotUnderlay extends LeafRenderObjectWidget {
  const _HistorySnapshotUnderlay({required this.image});

  final ui.Image image;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _HistorySnapshotRenderer(image);

  @override
  void updateRenderObject(
    BuildContext context,
    _HistorySnapshotRenderer renderObject,
  ) => renderObject.image = image;
}

class _HistorySnapshotRenderer extends RenderBox {
  _HistorySnapshotRenderer(ui.Image image)
    : _source = image,
      _image = image.clone();

  ui.Image _source;
  ui.Image _image;

  set image(ui.Image image) {
    if (image == _source) return;
    final previous = _image;
    _source = image;
    _image = image.clone();
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performResize() => size = computeDryLayout(constraints);

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderObject? ancestor = this;
    var origin = Offset.zero;
    while (ancestor != null && ancestor is! _HistoryRepaintBoundary) {
      final data = ancestor.parentData;
      if (data is BoxParentData) origin += data.offset;
      ancestor = ancestor.parent;
    }
    if (ancestor is! _HistoryRepaintBoundary || ancestor.size.isEmpty) return;
    // Align the image using layout offsets. The canvas already carries the
    // sheet's scale and translation; including them again crops its content.
    final target = Rect.fromLTWH(
      offset.dx - origin.dx,
      offset.dy - origin.dy,
      ancestor.size.width,
      ancestor.size.width * _image.height / _image.width,
    );
    context.canvas
      ..save()
      ..clipRect(offset & size)
      ..drawImageRect(
        _image,
        Rect.fromLTWH(0, 0, _image.width.toDouble(), _image.height.toDouble()),
        target,
        Paint()..filterQuality = FilterQuality.low,
      )
      ..restore();
  }

  @override
  void dispose() {
    final image = _image;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    super.dispose();
  }
}
