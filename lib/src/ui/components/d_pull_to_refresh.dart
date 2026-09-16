import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../foundation/tokens.dart';
import 'd_spinner.dart';

/// Pull down from the top of a vertical scrollable to refresh its contents.
///
/// The child owns its scroll controller and must use
/// [AlwaysScrollableScrollPhysics] to support short or empty content. Nested
/// scrollables and horizontal/reversed lists do not trigger a refresh. The
/// returned future keeps the indicator visible and prevents duplicate gestures.
/// Callers handle errors and present them alongside their retained content.
///
/// A null [onRefresh] disables new requests without replacing the child. Use a
/// key identifying the content when switching between independently loaded lists.
class DPullToRefresh extends StatefulWidget {
  const DPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.pullLabel = 'Pull to refresh',
    this.releaseLabel = 'Release to refresh',
    this.refreshingLabel = 'Refreshing',
    this.refreshLabel = 'Refresh',
  });

  final Future<void> Function()? onRefresh;
  final Widget child;
  final String pullLabel;
  final String releaseLabel;
  final String refreshingLabel;

  /// Screen-reader action for refreshing without a drag gesture.
  final String refreshLabel;

  @override
  State<DPullToRefresh> createState() => _DPullToRefreshState();
}

class _DPullToRefreshState extends State<DPullToRefresh> {
  final _indicator = GlobalKey<RefreshIndicatorState>();
  RefreshIndicatorStatus? _status;

  Future<void> _refresh() async {
    if (mounted) await widget.onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final busy =
        _status == RefreshIndicatorStatus.snap ||
        _status == RefreshIndicatorStatus.refresh;
    final visible =
        busy ||
        (widget.onRefresh != null &&
            (_status == RefreshIndicatorStatus.drag ||
                _status == RefreshIndicatorStatus.armed));
    final label = busy
        ? widget.refreshingLabel
        : _status == RefreshIndicatorStatus.armed
        ? widget.releaseLabel
        : widget.pullLabel;

    return Semantics(
      customSemanticsActions: widget.onRefresh == null
          ? null
          : {
              CustomSemanticsAction(label: widget.refreshLabel): () {
                unawaited(_indicator.currentState?.show());
              },
            },
      child: Stack(
        children: [
          RefreshIndicator.noSpinner(
            key: _indicator,
            onRefresh: _refresh,
            notificationPredicate: (notification) =>
                widget.onRefresh != null &&
                notification.depth == 0 &&
                notification.metrics.axisDirection == AxisDirection.down,
            onStatusChange: (status) {
              if (mounted) setState(() => _status = status);
            },
            child: widget.child,
          ),
          if (visible)
            Positioned(
              top: DSpacing.sm,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _status == RefreshIndicatorStatus.drag ? 0.5 : 1,
                    duration: DMotion.duration(context, DMotion.change),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.background,
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(DSpacing.md),
                        child: DSpinner(
                          color: tokens.foreground,
                          animating: busy,
                          semanticLabel: label,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
