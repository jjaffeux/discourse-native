import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/sheet_content_gesture_scope.dart';
import '../foundation/tokens.dart';
import 'd_page_surface.dart';
import 'd_spinner.dart';

/// Pull down from the top of a vertical scrollable to refresh its contents.
///
/// The child owns its scroll controller and must use
/// [AlwaysScrollableScrollPhysics] to support short or empty content. Nested
/// scrollables and horizontal/reversed lists do not trigger a refresh. The
/// spinner opens space above the content, below a floating [DPageSurface]
/// header. On release, that space settles to the loading height. The returned
/// future holds it there and prevents duplicate gestures; completion collapses
/// it without replacing the scrollable.
/// Callers handle errors and present them alongside their retained content.
///
/// A null [onRefresh] disables new requests without replacing the child. Use a
/// key identifying the content when switching between independently loaded lists.
/// In standard and page sheets, this content retains its pulls even while
/// refresh is disabled. The sheet's drag handle remains available for dismissal.
class DPullToRefresh extends StatefulWidget {
  const DPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this._pullLabel,
    this._releaseLabel,
    this._refreshingLabel,
    this._refreshLabel,
  });

  final Future<void> Function()? onRefresh;
  final Widget child;
  final String? _pullLabel;
  String get pullLabel => _pullLabel ?? appL10n.pullToRefresh;
  final String? _releaseLabel;
  String get releaseLabel => _releaseLabel ?? appL10n.releaseToRefresh;
  final String? _refreshingLabel;
  String get refreshingLabel => _refreshingLabel ?? appL10n.refreshing;

  final String? _refreshLabel;

  /// Screen-reader action for refreshing without a drag gesture.
  String get refreshLabel => _refreshLabel ?? appL10n.refresh;

  @override
  State<DPullToRefresh> createState() => _DPullToRefreshState();
}

class _DPullToRefreshState extends State<DPullToRefresh>
    with SingleTickerProviderStateMixin {
  static const _refreshExtent = 60.0;
  final _indicator = GlobalKey<RefreshIndicatorState>();
  late final _extent = AnimationController.unbounded(vsync: this);
  RefreshIndicatorStatus? _status;
  double _nativeOverscroll = 0;
  bool _ownsOverscroll = false;

  bool get _busy =>
      _status == RefreshIndicatorStatus.snap ||
      _status == RefreshIndicatorStatus.refresh;

  bool get _pulling =>
      _status == RefreshIndicatorStatus.drag ||
      _status == RefreshIndicatorStatus.armed;

  void _updateExtent() {
    if (_pulling && widget.onRefresh != null) {
      _extent.stop();
      return;
    }
    final target = _busy ? _refreshExtent : 0.0;
    if (_pulling || MediaQuery.disableAnimationsOf(context)) {
      _extent.value = target;
    } else {
      unawaited(
        _extent.animateTo(
          target,
          duration: DMotion.change,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(DPullToRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.onRefresh == null) != (widget.onRefresh == null)) {
      _updateExtent();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _updateExtent();
  }

  @override
  void dispose() {
    _extent.dispose();
    super.dispose();
  }

  bool _acceptScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axisDirection != AxisDirection.down) {
      return false;
    }

    final nativeOverscroll = math.max(
      0.0,
      notification.metrics.minScrollExtent - notification.metrics.pixels,
    );
    var changed = _nativeOverscroll != nativeOverscroll;
    _nativeOverscroll = nativeOverscroll;
    if (!_busy && !_pulling && _extent.value == 0 && nativeOverscroll == 0) {
      changed = changed || _ownsOverscroll;
      _ownsOverscroll = false;
    }
    final dragging = switch (notification) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (_pulling && dragging && widget.onRefresh != null) {
      final delta = switch (notification) {
        ScrollUpdateNotification(:final scrollDelta) => scrollDelta ?? 0,
        OverscrollNotification(:final overscroll) => overscroll / 2,
        _ => 0.0,
      };
      _extent.value = math.max(0.0, _extent.value - delta);
      changed = changed || delta != 0;
    }
    if (changed && mounted) {
      setState(() {});
    }
    return widget.onRefresh != null || _busy || _pulling;
  }

  Future<void> _refresh() async {
    if (mounted) await widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final busy = _busy;
    final visible =
        busy ||
        (widget.onRefresh != null &&
            ((_status == RefreshIndicatorStatus.drag && _extent.value > 0) ||
                _status == RefreshIndicatorStatus.armed));
    final label = busy
        ? widget.refreshingLabel
        : _status == RefreshIndicatorStatus.armed
        ? widget.releaseLabel
        : widget.pullLabel;
    final header = DPageSurface.headerGeometryOf(context);

    return SheetContentGestureRegion(
      child: Semantics(
        customSemanticsActions: widget.onRefresh == null
            ? null
            : {
                CustomSemanticsAction(label: widget.refreshLabel): () {
                  unawaited(_indicator.currentState?.show());
                },
              },
        child: AnimatedBuilder(
          animation: _extent,
          child: RefreshIndicator.noSpinner(
            key: _indicator,
            onRefresh: _refresh,
            notificationPredicate: _acceptScrollNotification,
            onStatusChange: (status) {
              if (mounted) {
                setState(() {
                  _status = status;
                  if (status != null) _ownsOverscroll = true;
                  _updateExtent();
                });
              }
            },
            child: widget.child,
          ),
          builder: (context, child) {
            final extent = _extent.value;
            final indicator = IgnorePointer(
              child: ClipRect(
                child: SizedBox(
                  height: extent,
                  child: Center(
                    child: Opacity(
                      opacity: _status == RefreshIndicatorStatus.drag ? 0.5 : 1,
                      child: DSpinner(
                        size: DSpacing.xl,
                        color: tokens.foreground,
                        animating: busy,
                        semanticLabel: label,
                      ),
                    ),
                  ),
                ),
              ),
            );
            return ClipRect(
              child: Stack(
                children: [
                  ClipRect(
                    clipper: _RefreshContentClipper(extent, header),
                    child: _RefreshContentInset(
                      offset:
                          extent - (_ownsOverscroll ? _nativeOverscroll : 0),
                      child: child,
                    ),
                  ),
                  if (visible)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: header?.inset(indicator) ?? indicator,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RefreshContentInset extends SingleChildRenderObjectWidget {
  const _RefreshContentInset({required this.offset, required super.child});

  final double offset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRefreshContentInset(offset);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRefreshContentInset renderObject,
  ) {
    renderObject.offset = offset;
  }
}

class _RenderRefreshContentInset extends RenderShiftedBox {
  _RenderRefreshContentInset(this._offset) : super(null);

  double _offset;
  set offset(double value) {
    if (_offset == value) return;
    _offset = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      constraints.copyWith(
        minHeight: math.max(0, constraints.minHeight - _offset),
        maxHeight: math.max(0, constraints.maxHeight - _offset),
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childSize = child!.getDryLayout(_childConstraints(constraints));
    return constraints.constrain(
      Size(childSize.width, childSize.height + _offset),
    );
  }

  @override
  void performLayout() {
    child!.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(
      Size(child!.size.width, child!.size.height + _offset),
    );
    (child!.parentData! as BoxParentData).offset = Offset(0, _offset);
  }
}

class _RefreshContentClipper extends CustomClipper<Rect> {
  _RefreshContentClipper(this.extent, this.header) : super(reclip: header);

  final double extent;
  final DPageHeaderGeometry? header;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    extent > 0
        ? math.min(size.height, extent + (header?.visibleExtent ?? 0))
        : 0,
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(_RefreshContentClipper oldClipper) =>
      extent != oldClipper.extent || header != oldClipper.header;
}
