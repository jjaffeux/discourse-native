import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// Mounts long HTML bodies across frames without splitting their DOM, selection
/// owner, or post identity. The completed body has ordinary column layout.
///
/// This bounds the number of new top-level widgets per frame, not the cost of
/// an individual table, code block, or deeply nested element.
class ProgressiveHtmlMode extends RenderMode {
  const ProgressiveHtmlMode();

  @override
  Widget buildBodyWidget(
    WidgetFactory wf,
    BuildContext context,
    List<Widget> children,
  ) => children.length <= _ProgressiveHtmlBodyState.batchSize * 2
      ? RenderMode.column.buildBodyWidget(wf, context, children)
      : _ProgressiveHtmlBody(children: children);
}

/// Lets the topic retain a known post height until every body block is mounted.
class HtmlBodyMountingNotification extends Notification {
  const HtmlBodyMountingNotification(this.completion);

  final Future<void> completion;
}

class _ProgressiveHtmlBody extends StatefulWidget {
  const _ProgressiveHtmlBody({required this.children});

  final List<Widget> children;

  @override
  State<_ProgressiveHtmlBody> createState() => _ProgressiveHtmlBodyState();
}

class _ProgressiveHtmlBodyState extends State<_ProgressiveHtmlBody> {
  // HTML's inter-paragraph margins are separate children, so this normally
  // mounts about 32 paragraphs: enough to cover the initial reading viewport.
  static const batchSize = 64;
  int _count = batchSize;
  final _completion = Completer<void>();

  @override
  void initState() {
    super.initState();
    HtmlBodyMountingNotification(_completion.future).dispatch(context);
    _HtmlMountQueue.add(this);
  }

  @override
  void didUpdateWidget(_ProgressiveHtmlBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.children, oldWidget.children)) return;
    // Once displayed, apply live edits and theme changes as a whole, preserving
    // the existing update behavior instead of shrinking back to a partial body.
    final wasComplete = _count >= oldWidget.children.length;
    _count = wasComplete ? widget.children.length : batchSize;
    _HtmlMountQueue.remove(this);
    if (_count < widget.children.length) {
      _HtmlMountQueue.add(this);
    } else if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  void mountNextBatch() {
    setState(() {
      _count = math.min(_count + batchSize, widget.children.length);
    });
    if (_count < widget.children.length) {
      _HtmlMountQueue.add(this);
    } else if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  @override
  void dispose() {
    _HtmlMountQueue.remove(this);
    if (!_completion.isCompleted) _completion.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _EstimatedBodyHeight(
    // Reserve the unseen tail using the measured prefix. Already-visible
    // paragraphs keep their final offsets as new content is appended below.
    factor: math.max(1.0, widget.children.length / _count),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widget.children.take(_count).toList(growable: false),
    ),
  );
}

// Retained offscreen posts and newly opened posts share the same queue. They
// must not each schedule an entire additional batch in the same frame.
abstract final class _HtmlMountQueue {
  static final _pending = <_ProgressiveHtmlBodyState>{};
  static int? _frame;

  static void add(_ProgressiveHtmlBodyState body) {
    _pending.add(body);
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      final next = _pending.first;
      _pending.remove(next);
      next.mountNextBatch();
      if (_pending.isNotEmpty) add(_pending.first);
    });
  }

  static void remove(_ProgressiveHtmlBodyState body) {
    _pending.remove(body);
    if (_pending.isNotEmpty || _frame == null) return;
    SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
    _frame = null;
  }
}

class _EstimatedBodyHeight extends SingleChildRenderObjectWidget {
  const _EstimatedBodyHeight({required this.factor, required super.child});

  final double factor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEstimatedBodyHeight(factor);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEstimatedBodyHeight renderObject,
  ) => renderObject.factor = factor;
}

class _RenderEstimatedBodyHeight extends RenderProxyBox {
  _RenderEstimatedBodyHeight(this._factor);

  double _factor;

  set factor(double value) {
    if (_factor == value) return;
    _factor = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(constraints.copyWith(minHeight: 0), parentUsesSize: true);
    size = constraints.constrain(
      Size(child!.size.width, child!.size.height * _factor),
    );
  }
}
