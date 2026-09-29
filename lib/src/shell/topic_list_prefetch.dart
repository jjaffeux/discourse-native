part of 'topic_list_view.dart';

/// Observes intent without participating in hit testing or changing DItem's
/// bounds. All input sources share one lease on the shell's prefetch request.
final class _TopicListPrefetch {
  _TopicListPrefetch(this.owner) {
    owner._keyboardFocus.addListener(_focusChanged);
  }

  final _TopicListViewState owner;
  final _rows = <_ConversationTopicCardState>{};
  final _predictor = TopicPointerPredictor<_ConversationTopicCardState>();
  Map<_ConversationTopicCardState, Rect> _bounds = {};
  bool _enabled = false;
  bool _scrolling = false;
  int? _frame;
  PointerHoverEvent? _pending;
  Timer? _expiry;
  VoidCallback? _release;
  (String, int, int?)? _key;
  TopicPrefetchIntent? _intent;

  bool get _usable =>
      _enabled && owner.mounted && navigationShortcutsAllowed(owner.context);

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    } else {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
      reset();
    }
  }

  void register(_ConversationTopicCardState row) => _rows.add(row);

  void unregister(_ConversationTopicCardState row) {
    _rows.remove(row);
    _bounds.remove(row);
    invalidate(_rowKey(row));
  }

  void invalidate((String, int, int?) key) {
    _predictor.reset();
    if (_key == key) _releaseCurrent();
  }

  void geometryChanged() {
    _resetPointer();
    if (_intent == TopicPrefetchIntent.trajectory) _releaseCurrent();
  }

  (String, int, int?) _rowKey(_ConversationTopicCardState row) =>
      (row.row.siteUrl, row.row.topic.id, row.row.topic.lastUnreadPostNumber);

  void hover(_ConversationTopicCardState row, bool hovered) {
    if (hovered) {
      if (!_usable || _scrolling) return;
      _select(row.row.siteUrl, row.row.topic, TopicPrefetchIntent.hover);
    } else if (_key == _rowKey(row) && _intent == TopicPrefetchIntent.hover) {
      _releaseCurrent();
    }
  }

  void keyboard(Topic topic) {
    if (!_usable) return;
    _resetPointer();
    final siteUrl = owner._controller?.currentInstance?.url;
    if (siteUrl != null) _select(siteUrl, topic, TopicPrefetchIntent.keyboard);
  }

  void _focusChanged() {
    if (_intent == TopicPrefetchIntent.keyboard &&
        !owner._keyboardFocus.hasFocus) {
      _releaseCurrent();
    }
  }

  void scroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) _scrolling = true;
    if (notification is ScrollEndNotification) _scrolling = false;
    _resetPointer();
    if (_intent != TopicPrefetchIntent.keyboard) _releaseCurrent();
  }

  void _pointer(PointerEvent event) {
    if (event is PointerRemovedEvent) {
      _resetPointer();
      if (_intent != TopicPrefetchIntent.keyboard) _releaseCurrent();
      return;
    }
    if (event is! PointerHoverEvent || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    if (!_enabled || _scrolling) return;
    _pending = event;
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback(_sample);
  }

  void _sample(Duration time) {
    _frame = null;
    final event = _pending;
    _pending = null;
    if (event == null) return;
    if (!_usable || _scrolling) {
      _resetPointer();
      if (_intent != TopicPrefetchIntent.keyboard) _releaseCurrent();
      return;
    }
    final targets = <_ConversationTopicCardState, Rect>{};
    for (final row in _rows) {
      if (!row.mounted) continue;
      final object = row._prefetchBounds.currentContext?.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(object);
      if (viewport == null) continue;
      final visible = MatrixUtils.transformRect(
        viewport.getTransformTo(null),
        viewport.paintBounds,
      );
      final rect = MatrixUtils.transformRect(
        object.getTransformTo(null),
        Offset.zero & object.size,
      ).intersect(visible);
      if (!rect.isEmpty) targets[row] = rect;
    }
    if (!mapEquals(_bounds, targets)) _predictor.reset();
    _bounds = targets;
    // A fresh move can restore hover after scrolling stopped under the mouse.
    for (final target in targets.entries) {
      if (target.value.contains(event.position)) {
        _predictor.reset();
        if (_isExposed(target.key, event.position, event.viewId)) {
          hover(target.key, true);
        } else if (_intent != TopicPrefetchIntent.keyboard) {
          _releaseCurrent();
        }
        return;
      }
    }
    final candidate = _predictor.sample(event.position, time, targets);
    if (candidate == null) {
      if (_intent == TopicPrefetchIntent.trajectory ||
          _intent == TopicPrefetchIntent.hover) {
        _releaseCurrent();
      }
      return;
    }
    final rect = targets[candidate]!;
    if (!_isExposed(candidate, rect.center, event.viewId)) {
      if (_intent == TopicPrefetchIntent.trajectory) _releaseCurrent();
      return;
    }
    _select(
      candidate.row.siteUrl,
      candidate.row.topic,
      TopicPrefetchIntent.trajectory,
    );
    _expiry?.cancel();
    _expiry = Timer(TopicPointerPredictor.historyAge, () {
      _predictor.reset();
      if (_intent == TopicPrefetchIntent.trajectory) _releaseCurrent();
    });
  }

  // An overlay can cover otherwise visible row geometry. This observes the
  // normal hit test; it never forwards or expands any interactive target.
  bool _isExposed(_ConversationTopicCardState row, Offset point, int viewId) {
    final box = row._prefetchBounds.currentContext?.findRenderObject();
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, point, viewId);
    for (final hit in result.path) {
      final target = hit.target;
      if (target is! RenderObject) continue;
      RenderObject? node = target;
      while (node != null) {
        if (identical(node, box)) return true;
        node = node.parent;
      }
    }
    return false;
  }

  void _select(String siteUrl, Topic topic, TopicPrefetchIntent intent) {
    final key = (siteUrl, topic.id, topic.lastUnreadPostNumber);
    _expiry?.cancel();
    _expiry = null;
    if (_key == key) {
      _intent = intent;
      return;
    }
    _releaseCurrent();
    _key = key;
    _intent = intent;
    _release = owner._controller?.prefetchTopic(
      siteUrl,
      topic,
      intent: intent,
      isInterested: () =>
          _usable &&
          _key == key &&
          owner.widget.feed.topicIds.contains(topic.id) &&
          (_intent != TopicPrefetchIntent.keyboard ||
              owner._keyboardFocus.hasFocus),
    );
  }

  void _releaseCurrent() {
    _expiry?.cancel();
    _expiry = null;
    _release?.call();
    _release = null;
    _key = null;
    _intent = null;
  }

  void _resetPointer() {
    if (_frame case final frame?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    }
    _frame = null;
    _pending = null;
    _bounds.clear();
    _predictor.reset();
  }

  void reset() {
    _scrolling = false;
    _resetPointer();
    _releaseCurrent();
  }

  void dispose() {
    setEnabled(false);
    reset();
    owner._keyboardFocus.removeListener(_focusChanged);
    _rows.clear();
  }
}
