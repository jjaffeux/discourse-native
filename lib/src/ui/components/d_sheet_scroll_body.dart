import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// A sheet body with a chip footer that moves out of the way while reading.
class DSheetScrollBody extends StatefulWidget {
  const DSheetScrollBody({
    super.key,
    required this.child,
    this.footer,
    this.fill = false,
  });

  final Widget child;
  final Widget? footer;
  final bool fill;

  @override
  State<DSheetScrollBody> createState() => _DSheetScrollBodyState();
}

class _DSheetScrollBodyState extends State<DSheetScrollBody> {
  static const _motion = Duration(milliseconds: 220);
  static const _hold = Duration(milliseconds: 250);
  static const _slack = 10.0;

  bool _hidden = false;
  double _travel = 0;
  Timer? _holdTimer;
  ({ScrollPosition position, double contentExtent})? _listEnd;

  double _contentExtent(ScrollMetrics metrics) =>
      metrics.maxScrollExtent -
      metrics.minScrollExtent +
      metrics.viewportDimension;

  bool _showAtEdge(ScrollMetrics metrics, BuildContext? origin) {
    if (metrics.extentBefore > 1 && metrics.extentAfter > 1) return false;
    if (_hidden &&
        metrics.extentAfter <= 1 &&
        metrics.extentBefore > 1 &&
        origin != null) {
      final position = Scrollable.maybeOf(origin)?.position;
      if (position != null) {
        _listEnd = (position: position, contentExtent: _contentExtent(metrics));
      }
    }
    _travel = 0;
    _setHidden(false);
    return true;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (widget.footer == null ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final metrics = notification.metrics;
    final origin = notification.context;
    if (_listEnd case final end?) {
      final position = Scrollable.maybeOf(origin)?.position;
      if (!identical(position, end.position) ||
          (_contentExtent(metrics) - end.contentExtent).abs() > 1) {
        _listEnd = null;
      } else if (metrics.extentAfter > 1) {
        end.position.jumpTo(end.position.maxScrollExtent);
      }
    }
    _showAtEdge(metrics, origin);
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (widget.footer == null ||
        notification is! ScrollUpdateNotification ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final metrics = notification.metrics;
    final delta = notification.scrollDelta ?? 0;
    if (delta < 0) _listEnd = null;
    if (_showAtEdge(metrics, notification.context) ||
        metrics.outOfRange ||
        delta == 0) {
      return false;
    }
    _travel = _travel.sign == delta.sign ? _travel + delta : delta;
    if (_holdTimer?.isActive != true) {
      if (_travel > _slack) _setHidden(true);
      if (_travel < -_slack) _setHidden(false);
    }
    return false;
  }

  void _setHidden(bool hidden) {
    if (_hidden == hidden) return;
    setState(() => _hidden = hidden);
    _holdTimer?.cancel();
    _holdTimer = Timer(_hold, () => _holdTimer = null);
  }

  @override
  void didUpdateWidget(DSheetScrollBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.footer == null) != (oldWidget.footer == null)) {
      _hidden = false;
      _travel = 0;
      _listEnd = null;
      _holdTimer?.cancel();
      _holdTimer = null;
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Flexible(
        fit: widget.fill ? FlexFit.tight : FlexFit.loose,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: _onMetrics,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.child,
          ),
        ),
      ),
      if (widget.footer case final footer?)
        ClipRect(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _hidden ? 0 : 1),
            duration: DMotion.duration(context, _motion),
            curve: _hidden
                ? const Cubic(.4, 0, 1, 1)
                : const Cubic(.32, .72, 0, 1),
            builder: (context, factor, child) => Align(
              alignment: Alignment.topCenter,
              heightFactor: factor,
              child: child,
            ),
            child: IgnorePointer(
              ignoring: _hidden,
              child: ExcludeFocus(
                excluding: _hidden,
                child: ExcludeSemantics(excluding: _hidden, child: footer),
              ),
            ),
          ),
        ),
    ],
  );
}
