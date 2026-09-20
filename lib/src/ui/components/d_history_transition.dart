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
///
/// Previews are in-memory snapshots, never additional live pages. Up to eight
/// recently visited pages are retained, at most one million pixels each.
/// Unvisited/evicted pages and platform views use the background as a fallback.
/// Theme, viewport, history and app lifecycle changes discard the previews.
/// Reduced motion keeps the page stationary while preserving the gestures.
class DHistoryTransition extends StatefulWidget {
  const DHistoryTransition({
    super.key,
    required this.history,
    required this.entry,
    required this.child,
    this.previousEntry,
    this.nextEntry,
    this.onBack,
    this.onForward,
  });

  final Object history;
  final Object entry;
  final Object? previousEntry;
  final Object? nextEntry;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final Widget child;

  @override
  State<DHistoryTransition> createState() => _DHistoryTransitionState();
}

class _DHistoryTransitionState extends State<DHistoryTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _boundary = GlobalKey();
  final _previews = <Object, ui.Image>{};
  final _pointers = <int>{};
  late final _progress = AnimationController(vsync: this);
  ui.Image? _preview;
  Object? _environment;
  Size _size = Size.zero;
  bool _back = false;
  bool _dragging = false;
  bool _settling = false;
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
    if (oldWidget.history != widget.history) {
      _clear();
    } else if (oldWidget.entry != widget.entry) {
      // The descendant still contains the outgoing page's last painted frame.
      // Capture it before rebuilding that one live renderer for the new entry.
      final boundary = _boundary.currentContext?.findRenderObject();
      if (boundary is _HistoryRepaintBoundary &&
          !MediaQuery.disableAnimationsOf(context)) {
        final image = boundary.snapshot(MediaQuery.devicePixelRatioOf(context));
        if (image != null) {
          _previews.remove(oldWidget.entry)?.dispose();
          _previews[oldWidget.entry] = image;
          while (_previews.length > 8) {
            _previews.remove(_previews.keys.first)!.dispose();
          }
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
    _resetGesture();
    _pointers.clear();
    for (final image in _previews.values) {
      image.dispose();
    }
    _previews.clear();
  }

  bool _allowsPointer(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch ||
        _pointers.length > 1 ||
        _dragging ||
        _settling ||
        !_routeIsCurrent ||
        _size.width <= 48) {
      return false;
    }
    final x = event.localPosition.dx;
    if (x > 24 && x < _size.width - 24) return false;
    final back = _rtl ? x >= _size.width - 24 : x <= 24;
    return back
        ? widget.previousEntry != null && widget.onBack != null
        : widget.nextEntry != null && widget.onForward != null;
  }

  void _start(DragStartDetails details) {
    if (_pointers.length != 1 || !_routeIsCurrent) return;
    setState(() {
      _back = _rtl
          ? details.localPosition.dx >= _size.width - 24
          : details.localPosition.dx <= 24;
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
        : _progress.value >= .25;
    unawaited(_settle(commit));
  }

  Future<void> _settle(bool commit) async {
    if (!_dragging) return;
    _dragging = false;
    _settling = true;
    final generation = ++_generation;
    try {
      await _progress
          .animateTo(
            commit ? 1 : 0,
            duration: DMotion.duration(context, DMotion.change),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _generation) return;
    final navigate = commit && _routeIsCurrent ? _navigate : null;
    setState(_resetGesture);
    navigate?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clear();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = DTokens.of(context).background;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_size != constraints.biggest) {
          _size = constraints.biggest;
          _clear();
        }
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
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _progress,
                child: _HistoryBoundary(key: _boundary, child: widget.child),
                builder: (context, child) {
                  final p = reducedMotion ? 0.0 : _progress.value;
                  final active = p > 0;
                  final preview = ExcludeSemantics(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: background,
                        child: _preview == null
                            ? null
                            : RawImage(image: _preview, fit: BoxFit.fill),
                      ),
                    ),
                  );
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (active && _back)
                        Transform.translate(
                          offset: Offset(
                            -_sign * _size.width * .25 * (1 - p),
                            0,
                          ),
                          child: preview,
                        ),
                      Transform.translate(
                        key: const ValueKey('history-live-page'),
                        offset: Offset(
                          _sign * _size.width * p * (_back ? 1 : .25),
                          0,
                        ),
                        child: IgnorePointer(
                          ignoring: _dragging || _settling,
                          child: ColoredBox(color: background, child: child),
                        ),
                      ),
                      if (active && !_back)
                        Transform.translate(
                          offset: Offset(-_sign * _size.width * (1 - p), 0),
                          child: preview,
                        ),
                    ],
                  );
                },
              ),
            ),
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
