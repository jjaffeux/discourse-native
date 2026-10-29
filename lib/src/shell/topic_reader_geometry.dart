part of 'topic_post_sliver.dart';

typedef _RetainedTopicPostExtent = ({
  double width,
  double height,
  WeakReference<Post> post,
  WeakReference<TopicDetail> topic,
  bool summary,
  bool summaryLoading,
  int readTimeWordCount,
});

RevealedOffset? getOffsetToRevealIfLaidOut(
  RenderAbstractViewport viewport,
  RenderObject target,
  double alignment,
) {
  var child = target;
  while (child.parent != viewport) {
    final parent = child.parent;
    if (parent == null) return null;
    if (parent is RenderSliver && parent.childScrollOffset(child) == null) {
      return null;
    }
    child = parent;
  }
  return viewport.getOffsetToReveal(target, alignment);
}

final class TopicPostWindow {
  TopicPostWindow(this.postIds, {required this.hasHeader})
    : _indexByPostId = {} {
    for (var index = 0; index < postIds.length; index++) {
      final postId = postIds[index];
      // Topic streams should contain unique ids. Preserve List.indexOf's
      // first-match behavior if a malformed payload repeats one anyway.
      if (!_indexByPostId.containsKey(postId)) {
        _indexByPostId[postId] = index;
      }
    }
  }

  final List<int> postIds;
  final bool hasHeader;

  int get leadingItems => hasHeader ? 1 : 0;
  final Map<int, int> _indexByPostId;

  TopicPostWindow._withHeader(TopicPostWindow source, this.hasHeader)
    : postIds = source.postIds,
      _indexByPostId = source._indexByPostId;

  TopicPostWindow withHeader(bool value) =>
      value == hasHeader ? this : TopicPostWindow._withHeader(this, value);

  bool represents(List<int> postIds) => identical(this.postIds, postIds);

  int? operator [](int postId) => _indexByPostId[postId];

  int childIndexForItem(int itemIndex) => itemIndex * 2;

  int childIndexForPostIndex(int postIndex) =>
      childIndexForItem(postIndex + leadingItems);

  int? childIndexForPost(int postId) {
    final index = this[postId];
    return index == null ? null : childIndexForPostIndex(index);
  }

  int? postIndexForChild(int childIndex) {
    if (childIndex.isOdd) return null;
    final index = childIndex ~/ 2 - leadingItems;
    return index >= 0 && index < postIds.length ? index : null;
  }

  Iterable<int> postIndexesInRange(
    (int, int)? range, {
    bool reverse = false,
  }) sync* {
    if (range == null) return;
    if (reverse) {
      for (var child = range.$2; child >= range.$1; child--) {
        final index = postIndexForChild(child);
        if (index != null) yield index;
      }
    } else {
      for (var child = range.$1; child <= range.$2; child++) {
        final index = postIndexForChild(child);
        if (index != null) yield index;
      }
    }
  }

  Key separatorKeyAfterItem(int itemIndex) {
    final next = itemIndex + 1 - leadingItems;
    return next < postIds.length
        ? ValueKey(('topic-post-separator', postIds[next]))
        : ValueKey(('topic-trailing-separator', next - postIds.length));
  }

  int? childIndexForKey(Key key) {
    if (key is ValueKey<int>) return childIndexForPost(key.value);
    if (key is ValueKey<(String, int)>) {
      final (kind, id) = key.value;
      if (kind == 'topic-post-separator') {
        final child = childIndexForPost(id);
        return child == null || child == 0 ? null : child - 1;
      }
      if (kind == 'topic-trailing-separator') {
        return childIndexForItem(postIds.length + leadingItems + id) - 1;
      }
    }
    return null;
  }
}

final class TopicReaderGeometry implements TopicViewportGeometry {
  TopicReaderGeometry({
    required this.scrollController,
    required this.listController,
    required this.topInset,
    required this.startsAtBeginning,
    required this.postFrame,
  });

  final ScrollController? Function() scrollController;
  final ListController? Function() listController;
  final double Function() topInset;
  final bool Function() startsAtBeginning;
  final TopicViewportPostFrameScheduler postFrame;

  final Map<int, BuildContext> _postContexts = {};
  final Map<int, _RetainedTopicPostExtent> _retainedPostExtents = {};
  TopicPostWindow _window = TopicPostWindow(const [], hasHeader: false);
  GlobalKey _sliverKey = GlobalKey();
  int _extentGeneration = 0;
  double postWidth = 0;

  ScrollController? get _scroll => scrollController();
  ListController? get _list => listController();
  TopicPostWindow get window => _window;
  GlobalKey get sliverKey => _sliverKey;
  int get extentGeneration => _extentGeneration;

  int? Function(Key) get findChildIndexCallback {
    final mapping = window;
    return (key) {
      final child = mapping.childIndexForKey(key);

      return child;
    };
  }

  int get attachedPostCount => _postContexts.length;
  BuildContext? postContext(int? postId) => _postContexts[postId];

  static double estimateChildExtent(int? index, double _) =>
      index == null ? 0 : (index.isOdd ? 1 : 199);

  void clear() {
    _sliverKey = GlobalKey();
    _extentGeneration++;
    _window = TopicPostWindow(const [], hasHeader: false);
    _postContexts.clear();
    _retainedPostExtents.clear();
    postWidth = 0;
  }

  void attachPost(int postId, BuildContext context) =>
      _postContexts[postId] = context;

  void detachPost(int postId, BuildContext context) {
    if (identical(_postContexts[postId], context)) _postContexts.remove(postId);
  }

  @override
  double get viewportTopInset => topInset();

  @override
  bool get canCorrectAnchor =>
      _list?.isAttached == true && _scroll?.hasClients == true;

  @override
  TopicViewportScrollPosition get scrollPosition {
    final position = _scroll!.position;
    return (
      pixels: position.pixels,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
  }

  @override
  void jumpToPixels(double pixels) => _scroll!.jumpTo(pixels);

  /// The scroll offset that puts a saved reading position [viewportOffset]
  /// into item [itemIndex], kept inside the item's current extent.
  double? offsetForItem(
    int itemIndex, {
    required double viewportOffset,
    bool startsAtBeginning = false,
  }) {
    if (itemIndex == 0 && viewportOffset == 0 && startsAtBeginning) return 0;
    return _offsetForItem(
      itemIndex,
      _constrainItemViewportOffset(itemIndex, viewportOffset),
    );
  }

  double? _offsetForItem(int itemIndex, double viewportOffset) {
    final render = sliverKey.currentContext?.findRenderObject();
    if (render is! _TopicPostRenderSliver || render.geometry == null) {
      return null;
    }
    return render.getOffsetToReveal(
          window.childIndexForItem(itemIndex),
          0,
          estimationOnly: true,
        ) -
        viewportOffset -
        viewportTopInset;
  }

  @override
  double constrainPostViewportOffset(int postId, double viewportOffset) {
    final index = window[postId];
    return index == null
        ? viewportOffset
        : _constrainItemViewportOffset(
            index + window.leadingItems,
            viewportOffset,
          );
  }

  double _constrainItemViewportOffset(int itemIndex, double viewportOffset) {
    if (viewportOffset >= 0) return viewportOffset;
    final list = _list;
    final childIndex = window.childIndexForItem(itemIndex);
    final extent =
        list != null && list.isAttached && childIndex < list.numberOfItems
        ? list.extentForIndex(childIndex).$1
        : 0.0;
    // Keep the anchor in the laid-out range while an estimated or partially
    // mounted post grows. Its saved offset becomes reachable as layout fills in.
    return viewportOffset
        .clamp(-(extent - 1).clamp(0, double.infinity), 0)
        .toDouble();
  }

  /// The scroll offset that puts post [postId] at [viewportOffset], as given.
  double? offsetForPost(int postId, {required double viewportOffset}) {
    final index = window[postId];
    return index == null
        ? null
        : _offsetForItem(index + window.leadingItems, viewportOffset);
  }

  @override
  void jumpToPost(int index, {double viewportOffset = 0}) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) {
      return;
    }
    if (!list.isAttached || !scroll.hasClients) {
      return;
    }

    // `separated` interleaves a separator after every logical item, and the
    // ListController addresses that expanded child list.
    if (index == 0 && viewportOffset == 0 && startsAtBeginning()) {
      scroll.jumpTo(scroll.position.minScrollExtent);
      return;
    } else {
      list.jumpToItem(
        index: window.childIndexForItem(index),
        scrollController: scroll,
        alignment: 0,
      );
    }
    final targetInset = viewportOffset + viewportTopInset;
    if (targetInset == 0 || !scroll.hasClients) {
      return;
    }
    final position = scroll.position;
    scroll.jumpTo(
      (position.pixels - targetInset)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
  }

  void _invalidateExtents() {
    final list = _list;
    if (list == null || !list.isAttached) return;
    if (!list.isLocked) {
      list.invalidateAllExtents();
      return;
    }

    final generation = extentGeneration;
    postFrame(() {
      final current = _list;
      if (!identical(current, list) || extentGeneration != generation) return;
      if (current == null || !current.isAttached || current.isLocked) return;

      current.invalidateAllExtents();
    });
  }

  bool _shiftExtents(TopicViewportWindowChange change) {
    final list = _list;
    if (list == null || !list.isAttached || list.isLocked) return false;
    final previous = change.previousPostIds;
    final current = change.currentPostIds;
    if (previous.isEmpty) return false;
    final inserted = current.indexOf(previous.first);
    if (inserted < 0 || current.length < previous.length + inserted) {
      return false;
    }
    for (var index = 0; index < previous.length; index++) {
      if (previous[index] != current[index + inserted]) return false;
    }
    final previousLeading = change.previousHasHeader ? 1 : 0;
    if (list.numberOfItems < (previous.length + previousLeading) * 2 - 1) {
      return false;
    }

    // The sliver keeps heights by child index, while its keyed elements move
    // with post IDs. Move the cached heights too, before updating the delegate;
    // invalidating them alone leaves old heights assigned to different posts.
    // Separated lists have two children per inserted post or loading header.
    final previousTotalExtent = list.totalExtent;
    if (change.previousHasHeader && !change.hasHeader) {
      list
        ..removeItem(0)
        ..removeItem(0);
    } else if (!change.previousHasHeader && change.hasHeader) {
      list
        ..addItem(0)
        ..addItem(1);
    }
    final leading = change.hasHeader ? 2 : 0;
    for (var child = 0; child < inserted * 2; child++) {
      list.addItem(leading + child);
    }
    if (inserted > 0) {
      // The old first post may gain or lose a day/time-gap divider now that
      // its predecessor is loaded. Other retained posts keep their neighbors.
      list.invalidateExtent(leading + inserted * 2);
      if (change.hasHeader) list.invalidateExtent(1);
    }
    final scroll = _scroll;
    if (scroll != null && scroll.hasClients) {
      // Move the viewport by the inserted estimates before layout. Unlike a
      // post-frame jump, this correction preserves an active drag's activity.
      scroll.position.correctBy(list.totalExtent - previousTotalExtent);
    }

    return true;
  }

  /// The extent the list measured for [postId]'s row the last time it was laid
  /// out, or null while the list only estimates it.
  double? measuredExtentFor(int postId) {
    final list = _list;
    if (list == null || !list.isAttached) return null;
    final childIndex = window.childIndexForPost(postId);
    if (childIndex == null || childIndex >= list.numberOfItems) return null;
    final (extent, estimated) = list.extentForIndex(childIndex);
    return estimated ? null : extent;
  }

  bool rememberPostExtent(
    int postId, {
    required Post post,
    required TopicViewportSnapshot snapshot,
  }) {
    final list = _list;
    if (list == null || !list.isAttached) return false;
    final childIndex = window.childIndexForPost(postId);
    if (childIndex == null || childIndex >= list.numberOfItems) return false;
    final extent = list.extentForIndex(childIndex);
    if (extent.$2) return false;
    final topic = snapshot.topic;
    if (topic == null) {
      return false;
    }
    final width = postWidth;
    final height = extent.$1;
    final previous = _retainedPostExtents[postId];
    // Do not let the asynchronous loading frame replace a settled extent for
    // the same post. A changed post or topic gets a fresh measurement instead.
    if (previous != null &&
        identical(previous.post.target, post) &&
        identical(previous.topic.target, topic) &&
        previous.summary == snapshot.summary &&
        previous.summaryLoading == snapshot.summaryLoading &&
        previous.readTimeWordCount == snapshot.readTimeWordCount &&
        (previous.width - width).abs() < 0.5 &&
        previous.height >= height - 0.5) {
      return false;
    }
    _retainedPostExtents[postId] = (
      width: width,
      height: height,
      post: WeakReference(post),
      topic: WeakReference(topic),
      summary: snapshot.summary,
      summaryLoading: snapshot.summaryLoading,
      readTimeWordCount: snapshot.readTimeWordCount,
    );
    return true;
  }

  double? minimumHeightFor(
    int postId, {
    required Post? post,
    required TopicViewportSnapshot snapshot,
  }) {
    final retained = _retainedPostExtents[postId];
    if (retained == null ||
        post == null ||
        snapshot.topic == null ||
        !identical(retained.post.target, post) ||
        !identical(retained.topic.target, snapshot.topic) ||
        retained.summary != snapshot.summary ||
        retained.summaryLoading != snapshot.summaryLoading ||
        retained.readTimeWordCount != snapshot.readTimeWordCount ||
        (retained.width - postWidth).abs() >= 0.5) {
      return null;
    }
    return retained.height;
  }

  ({double top, double bottom})? boundsForPost(int postId) {
    final context = _postContexts[postId];
    final scroll = _scroll;
    if (context == null || scroll == null || !scroll.hasClients) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return null;
    final revealed = getOffsetToRevealIfLaidOut(viewport, renderObject, 0);
    if (revealed == null) return null;
    final top = revealed.offset - scroll.position.pixels - viewportTopInset;
    return (top: top, bottom: top + renderObject.size.height);
  }

  @override
  double? postViewportOffset(int postId) => boundsForPost(postId)?.top;

  @override
  TopicViewportAnchor? captureAnchor(
    List<int> postIds, {
    required bool hasHeader,
  }) {
    final list = _list;
    final scroll = _scroll;
    if (list == null || scroll == null) return null;
    if (!list.isAttached || !scroll.hasClients) return null;
    final range = list.visibleRange;
    if (range == null) return null;

    final mapping = window.withHeader(hasHeader);
    for (final postIndex in mapping.postIndexesInRange(range)) {
      final viewportOffset = postViewportOffset(postIds[postIndex]);
      if (viewportOffset == null) continue;
      return (postId: postIds[postIndex], viewportOffset: viewportOffset);
    }
    return null;
  }

  void applyWindowChange(TopicViewportWindowChange change) {
    _window = window.represents(change.currentPostIds)
        ? window.withHeader(change.hasHeader)
        : TopicPostWindow(change.currentPostIds, hasHeader: change.hasHeader);
    switch (change.extentAction) {
      case TopicViewportExtentAction.none:
        return;
      case TopicViewportExtentAction.invalidate:
        if (!_shiftExtents(change)) _invalidateExtents();
        return;
      case TopicViewportExtentAction.replace:
        _extentGeneration++;
        _sliverKey = GlobalKey();
    }
  }
}
