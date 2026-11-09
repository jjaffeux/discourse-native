import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'nested_replies_api.dart';
import 'nested_replies_controller.dart';
import 'nested_replies_data.dart';

part 'nested_replies_reader_memory.dart';
part 'nested_replies_reader_scroll.dart';
part 'nested_replies_reader_loader.dart';
part 'nested_replies_reader_view.dart';

class NestedRepliesReader extends StatefulWidget {
  const NestedRepliesReader({
    super.key,
    required this.reader,
    required this.api,
    required this.settings,
    this.memory,
  });
  final PluginTopicReader reader;
  final NestedRepliesApi api;
  final NestedRepliesSettings settings;
  final NestedRepliesReaderMemory? memory;

  @override
  State<NestedRepliesReader> createState() => _NestedRepliesReaderState();
}

class _NestedRepliesReaderState extends State<NestedRepliesReader> {
  late final NestedRepliesController _controller;
  late final _NestedRepliesScrollController _scroll;
  final GlobalKey _viewport = GlobalKey();
  final Map<int, GlobalKey> _postKeys = {};
  final Map<(int, int), GlobalKey> _boundaryKeys = {};
  final Map<int, FocusNode> _collapseFocus = {};
  final Map<int, String> _revealed = {};
  final Set<int> _revealing = {};
  final Map<int, Object> _revealErrors = {};
  final Set<int> _liveReads = {};
  StreamSubscription<Object?>? _events;
  Timer? _timing;
  Timer? _refresh;
  Timer? _rememberTimer;
  late Object _memoryKey;
  _RememberedReader? _restore;
  bool _restoring = true;
  bool _restoringPagingAnchor = false;
  bool _applyingAnchorCorrection = false;
  double _restoreMotionDelta = 0;
  double? _pagingAnchorCacheExtent;
  int _pagingAnchorSettleFrames = 0;
  bool _scheduled = false;
  bool _saveGraphAfterFrame = false;
  late bool _wasForeground;
  Set<int> _timingCandidates = {};
  int _memoryRevision = 0;

  PluginTopicReader get reader => widget.reader;

  Object _memoryKeyFor({
    required NestedRepliesSort sort,
    required int? target,
    required int? context,
    required String? collapse,
  }) => (
    reader.siteUrl,
    reader.tabId,
    reader.topicId,
    sort,
    target,
    context,
    collapse,
    widget.settings.maxDepth,
    widget.settings.capDepth,
  );

  @override
  void initState() {
    super.initState();
    _wasForeground = reader.foreground;
    _memoryRevision =
        widget.memory?.revision(reader.siteUrl, reader.topicId) ?? 0;
    widget.memory?.addListener(_invalidated);
    final query = nestedRepliesQuery(reader.route.topicQuery);
    final sort =
        NestedRepliesSort.parse(query['sort']) ?? widget.settings.defaultSort;
    final requestedContext = int.tryParse(query['context'] ?? '');
    final context =
        requestedContext != null &&
            requestedContext >= 0 &&
            requestedContext <= 100
        ? requestedContext
        : null;
    final target = reader.route.postNumber == TopicLink.lastPostNumber
        ? reader.topic?.highestPostNumber
        : reader.route.postNumber;
    _memoryKey = _memoryKeyFor(
      sort: sort,
      target: target,
      context: context,
      collapse: query['collapse_replies'],
    );
    _restore = widget.memory?._take(_memoryKey);
    _scroll = _NestedRepliesScrollController(
      initialScrollOffset: _restore?.offset ?? 0,
    )..addListener(_onScroll);
    _controller = NestedRepliesController(
      loader: NestedRepliesReaderLoader(reader: reader, api: widget.api),
      settings: widget.settings,
    )..addListener(_changed);
    _events = reader.topicEvents.listen(_onEvent);
    reader.addListener(_readerChanged);
    _timing = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _observe(timing: true),
    );
    final snapshot = _restore?.snapshot;
    if (snapshot != null) {
      _controller.restore(snapshot);
      _scheduleObservation();
      if (reader.foreground) unawaited(_visitRestored());
    } else {
      unawaited(
        _open(
          target: target,
          context: context,
          sort: sort,
          collapse: query['collapse_replies'] == 'true',
          visit: true,
        ),
      );
    }
  }

  Future<void> _visitRestored() async {
    await _controller.refreshVisit(beforeApply: _prepareAnchorRestore);
    if (!mounted || !reader.isCurrent) return;
    if (_controller.error == null && reader.foreground) {
      unawaited(reader.reconcileVisit());
    }
    _scheduleObservation();
  }

  Future<void> _open({
    int? target,
    int? context,
    NestedRepliesSort? sort,
    bool? collapse,
    bool visit = false,
  }) async {
    await _controller.open(
      postNumber: target ?? _controller.targetPostNumber,
      context: context ?? _controller.contextDepth,
      sort: sort ?? _controller.requestedSort,
      collapse: collapse ?? _controller.collapseReplies,
      foreground: visit && reader.foreground,
    );
    if (!mounted || !reader.isCurrent) return;
    for (final number in _restore?.collapsed ?? const <int>{}) {
      _controller.setCollapsed(number, true);
    }
    if (visit && _controller.error == null && reader.foreground) {
      unawaited(reader.reconcileVisit());
    }
    _scheduleObservation();
  }

  void _invalidated() {
    if (!mounted || !reader.isCurrent) return;
    final revision =
        widget.memory?.revision(reader.siteUrl, reader.topicId) ?? 0;
    if (revision == _memoryRevision) return;
    _memoryRevision = revision;
    unawaited(_reload());
  }

  void _readerChanged() {
    if (!mounted) return;
    final foreground = reader.foreground;
    if (!foreground) {
      _remember();
      _timingCandidates.clear();
    } else if (!_wasForeground) {
      unawaited(_visitRestored());
    }
    _wasForeground = foreground;
    setState(() {});
    _scheduleObservation();
  }

  void _changed() {
    if (!mounted) return;
    _saveGraphAfterFrame = true;
    setState(() {});
    _scheduleObservation();
  }

  void _scheduleObservation() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _restoreAnchor();
      _observe();
      _loadViewportDemand();
      if (_saveGraphAfterFrame &&
          !_controller.loading &&
          !_controller.restoringPages) {
        _saveGraphAfterFrame = false;
        _remember();
      }
    });
  }

  void _onScroll() {
    _scheduleObservation();
    _rememberTimer?.cancel();
    _rememberTimer = Timer(const Duration(milliseconds: 160), _remember);
  }

  void _collapsePost(int postNumber, bool collapsed) {
    _finishAnchorRestore();
    final projection = _displayedRows(includeCollapsed: true);
    final row = projection.rows
        .where((row) => row.node.postNumber == postNumber)
        .firstOrNull;
    final suppressed =
        row != null &&
        !_controller.isExpanded(postNumber, depth: row.actualDepth);
    _controller.setCollapsed(postNumber, collapsed);
    if (!collapsed &&
        suppressed &&
        row.actualDepth < widget.settings.maxDepth &&
        (!_usesMobileLayout ||
            row.depth - projection.depthOffset < _phoneDepthLimit)) {
      unawaited(_loadChildren(postNumber, depth: row.actualDepth + 1));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = _collapseFocus[postNumber];
      if (focus?.context != null) focus!.requestFocus();
    });
  }

  List<({int number, int id, double top})> _visible({
    bool readableOnly = true,
  }) {
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return const [];
    }
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    final readableIds = readableOnly
        ? _readablePostIds()
        : {
            if (_controller.op case final op?)
              if (!op.data.hiddenDeleted) op.postId,
            for (final row in _displayedRows().rows) row.node.postId,
          };
    final visible = <({int number, int id, double top})>[];
    for (final entry in _postKeys.entries) {
      if (!readableIds.contains(entry.key) ||
          (readableOnly &&
              (_controller.post(entry.key)?.data.redacted ?? false))) {
        continue;
      }
      final box = entry.value.currentContext?.findRenderObject();
      final post = reader.post(entry.key);
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          post == null ||
          (readableOnly && post.contentRedacted)) {
        continue;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final overlap = bounds.intersect(rect);
      if (overlap.width > 0 &&
          overlap.height >= math.min(64, rect.height / 2)) {
        visible.add((
          number: post.postNumber,
          id: post.id,
          top: rect.top - bounds.top,
        ));
      }
    }
    visible.sort((a, b) => a.top.compareTo(b.top));
    return visible;
  }

  Set<int> _readablePostIds() => {
    if (_controller.op case final op?)
      if (!op.data.hiddenDeleted) op.postId,
    for (final row in _displayedRows().rows)
      if (!_controller.isCollapsed(row.node.postNumber)) row.node.postId,
  };

  void _observe({bool timing = false}) {
    if (!reader.foreground) return;
    final visible = _visible();
    reader.setVisiblePostIds(_readablePostIds());
    if (timing) {
      final current = visible.map((post) => post.number).toSet();
      final exposed = current.intersection(_timingCandidates);
      _timingCandidates = current;
      if (exposed.isNotEmpty) {
        unawaited(reader.observeVisible(exposed));
      }
    }
  }

  _RememberedReader? _captureAnchor() {
    if (!_scroll.hasClients) return null;
    final visible = _visible(readableOnly: false);
    return _RememberedReader(
      siteUrl: reader.siteUrl,
      offset: _scroll.offset,
      collapsed: _controller.collapsedPostNumbers,
      topicId: reader.topicId,
      revision: _memoryRevision,
      snapshot: _controller.snapshot(),
      anchor: visible.firstOrNull?.id,
      anchorOffset: visible.firstOrNull?.top,
    );
  }

  void _remember() {
    if (!reader.isCurrent ||
        _controller.loading ||
        _controller.error != null ||
        _controller.restoringPages) {
      return;
    }
    final saved = _captureAnchor();
    if (saved != null) widget.memory?._put(_memoryKey, saved);
  }

  void _prepareAnchorRestore() {
    final saved = _captureAnchor();
    if (saved == null) return;
    _restore = saved;
    _restoreMotionDelta = 0;
    _restoring = true;
  }

  Future<void> _reload() async {
    await _controller.reload(beforeApply: _prepareAnchorRestore);
    if (mounted && reader.isCurrent) _scheduleObservation();
  }

  Future<void> _changeSort(NestedRepliesSort sort) async {
    if (sort == _controller.requestedSort) return;
    _remember();
    final query = {
      ...nestedRepliesQuery(reader.route.topicQuery),
      'sort': sort.wireValue,
    };
    if (!reader.updateQuery(Uri(queryParameters: query).query)) return;
    _memoryKey = _memoryKeyFor(
      sort: sort,
      target: _controller.targetPostNumber,
      context: _controller.contextDepth,
      collapse: query['collapse_replies'],
    );
    _finishAnchorRestore();
    _timingCandidates.clear();
    await _controller.changeSort(sort, foreground: reader.foreground);
    if (!mounted || !reader.isCurrent) return;
    if (_controller.error == null && reader.foreground) {
      unawaited(reader.reconcileVisit());
    }
    _scheduleObservation();
  }

  void _restoreAnchor() {
    if (!reader.isCurrent) {
      _finishAnchorRestore();
      return;
    }
    if (!_restoring ||
        _controller.loading ||
        _controller.restoringPages ||
        !_scroll.hasClients) {
      return;
    }
    final saved = _restore;
    if (saved != null && saved.anchor != null) {
      final box = _postKeys[saved.anchor]?.currentContext?.findRenderObject();
      final viewport = _viewport.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          viewport is RenderBox &&
          viewport.attached &&
          viewport.hasSize) {
        final top =
            box.localToGlobal(Offset.zero).dy -
            viewport.localToGlobal(Offset.zero).dy;
        final destination =
            (_scroll.offset +
                    top -
                    (saved.anchorOffset ?? 0) +
                    _restoreMotionDelta)
                .clamp(0.0, _scroll.position.maxScrollExtent);
        if ((destination - _scroll.offset).abs() > 1) {
          _applyingAnchorCorrection = true;
          try {
            _scroll.correctAnchor(destination);
          } finally {
            _applyingAnchorCorrection = false;
          }
        }
        if (_restoringPagingAnchor && _pagingAnchorSettleFrames > 0) {
          _pagingAnchorSettleFrames--;
          setState(() {});
          _scheduleObservation();
          return;
        }
      } else if (_restoringPagingAnchor) {
        final present =
            _displayedRows().rows.any(
              (row) => row.node.postId == saved.anchor,
            ) ||
            _controller.op?.postId == saved.anchor;
        if (present) {
          setState(
            () => _pagingAnchorCacheExtent = math.max(
              math.min(
                (_pagingAnchorCacheExtent ?? 0) * 2,
                double.maxFinite / 4,
              ),
              _scroll.position.maxScrollExtent +
                  _scroll.position.viewportDimension,
            ),
          );
          _scheduleObservation();
          return;
        }
      }
    }
    _finishAnchorRestore();
  }

  void _finishAnchorRestore() {
    _restoring = false;
    _restore = null;
    _restoreMotionDelta = 0;
    _restoringPagingAnchor = false;
    if (_pagingAnchorCacheExtent != null) {
      setState(() => _pagingAnchorCacheExtent = null);
    }
  }

  void _navigate({int? target, int? context, bool? collapse}) {
    _remember();
    final query = {...nestedRepliesQuery(reader.route.topicQuery)};
    query['sort'] = _controller.requestedSort.wireValue;
    if (context == null) {
      query.remove('context');
    } else {
      query['context'] = '$context';
    }
    if (collapse != null) {
      if (collapse) {
        query['collapse_replies'] = 'true';
      } else {
        query.remove('collapse_replies');
      }
    }
    reader.navigate(
      postNumber: target,
      query: Uri(queryParameters: query).query,
    );
  }

  void _onEvent(Object? event) {
    if (!reader.isCurrent || !reader.foreground || event is! Map) return;
    final type = event['type'];
    const changes = {
      'created',
      'revised',
      'rebaked',
      'deleted',
      'destroyed',
      'recovered',
      'acted',
      'liked',
      'unliked',
    };
    if (!changes.contains(type) && event['reload_topic'] != true) return;
    final id = nestedPositiveInt(event['id']);
    if (type == 'created' && id != null) {
      unawaited(_created(id));
      return;
    }
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 180), () {
      if (mounted && reader.foreground) unawaited(_reload());
    });
  }

  Future<void> _created(int id) async {
    if (_controller.post(id) != null || !_liveReads.add(id)) return;
    try {
      final accepted = await reader.ingest((request) async {
        final page = await widget.api.createdContext(
          siteUrl: reader.siteUrl,
          topicId: reader.topicId,
          slug: reader.route.slug ?? 'topic',
          credentials: request,
          sort: _controller.effectiveSort,
          postId: id,
        );
        return TopicContentResult(
          value: page.target,
          posts: page.posts.map(
            (payload) => TopicContentPost(
              payload.post,
              disposition: payload.redacted
                  ? TopicContentDisposition.redacted
                  : TopicContentDisposition.complete,
            ),
          ),
        );
      });
      if (!mounted ||
          !reader.isCurrent ||
          accepted == null ||
          !accepted.postIds.contains(id)) {
        return;
      }
      final node = accepted.value;
      final own = reader.post(id)?.userId == reader.currentUserId;
      if (node.data.isRoot) {
        if (!_controller.contextMode) _controller.queueRoot(node, own: own);
      } else if (own &&
          mounted &&
          MediaQuery.sizeOf(context).width < 600 &&
          (node.data.replyToPostNumber ?? 0) > 1) {
        _navigate(target: node.data.replyToPostNumber, context: 0);
      } else {
        unawaited(_reload());
      }
    } catch (_) {
      if (mounted && reader.foreground) unawaited(_reload());
    } finally {
      _liveReads.remove(id);
    }
  }

  Future<void> _reveal(NestedReplyNode node) async {
    if (!reader.foreground || !_revealing.add(node.postId)) return;
    setState(() {
      _revealErrors.remove(node.postId);
    });
    try {
      final receipt = await reader.ingest(
        (request) async => TopicContentResult(
          value: await widget.api.revealIgnored(
            siteUrl: reader.siteUrl,
            postId: node.postId,
            credentials: request,
          ),
        ),
      );
      if (mounted && reader.isCurrent && receipt != null) {
        setState(() {
          _revealed[node.postId] = receipt.value;
        });
      }
    } catch (error) {
      if (mounted && reader.isCurrent) {
        setState(() {
          _revealErrors[node.postId] = error;
        });
      }
    } finally {
      _revealing.remove(node.postId);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _remember();
    _timing?.cancel();
    _refresh?.cancel();
    _rememberTimer?.cancel();
    unawaited(_events?.cancel());
    reader.removeListener(_readerChanged);
    widget.memory?.removeListener(_invalidated);
    _controller.removeListener(_changed);
    _controller.dispose();
    for (final focus in _collapseFocus.values) {
      focus.dispose();
    }
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  bool get _usesMobileLayout => context.isTouch;

  int get _phoneDepthLimit {
    final lane = ContentReadingLane.geometryFor(
      context,
      availableWidth: MediaQuery.sizeOf(context).width,
    );
    return math.max(1, ((lane.width - 250) / 16).floor());
  }

  ({List<NestedVisibleEntry> entries, int depthOffset}) _displayedEntries({
    bool includeCollapsed = false,
  }) {
    var entries = _controller.visibleEntries(
      includeCollapsed: includeCollapsed,
    );
    var baseDepth = 0;
    if (_usesMobileLayout && _controller.contextMode) {
      final target = _controller.targetPostNumber;
      entries = entries
          .where(
            (entry) =>
                entry.node.postNumber == target ||
                entry.actualAncestorPostNumbers.contains(target),
          )
          .toList(growable: false);
      final firstRow = entries.whereType<NestedVisibleRow>().firstOrNull;
      baseDepth = firstRow?.depth ?? entries.firstOrNull?.depth ?? 0;
    }
    return (
      entries: [
        for (final entry in entries)
          if (!_usesMobileLayout || entry.depth - baseDepth <= _phoneDepthLimit)
            entry,
      ],
      depthOffset: baseDepth,
    );
  }

  ({List<NestedVisibleRow> rows, int depthOffset}) _displayedRows({
    bool includeCollapsed = false,
  }) {
    final projection = _displayedEntries(includeCollapsed: includeCollapsed);
    return (
      rows: projection.entries.whereType<NestedVisibleRow>().toList(
        growable: false,
      ),
      depthOffset: projection.depthOffset,
    );
  }

  void _preparePagingAnchorRestore() {
    _prepareAnchorRestore();
    _restoringPagingAnchor = _restore?.anchor != null;
    // Canonical cooked bodies join layout on the following frame.
    _pagingAnchorSettleFrames = 2;
  }

  Future<void> _loadMoreRoots() =>
      _controller.loadMoreRoots(beforeApply: _preparePagingAnchorRestore);

  Future<void> _loadChildren(int postNumber, {required int depth}) =>
      _controller.loadChildren(
        postNumber,
        depth: depth,
        beforeApply: _preparePagingAnchorRestore,
      );

  void _loadViewportDemand() {
    if (!mounted ||
        !reader.isCurrent ||
        !reader.foreground ||
        _restoring ||
        _controller.loading ||
        _controller.restoringPages ||
        _controller.error != null ||
        !_scroll.hasClients) {
      return;
    }
    final prefetch = paginationPrefetchDistance(_scroll.position);
    final rootPaging = ScrollPagingGate(
      hasMore: _controller.hasMoreRoots,
      busy: _controller.loadingMoreRoots,
      lastPageFailed: _controller.rootPageError != null,
    );
    if (rootPaging.admits && _scroll.position.extentAfter <= prefetch) {
      unawaited(_loadMoreRoots());
    }
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return;
    }
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    final projection = _displayedEntries();
    for (final boundary
        in projection.entries.whereType<NestedChildrenBoundary>()) {
      if (_usesMobileLayout &&
          boundary.depth - projection.depthOffset >= _phoneDepthLimit) {
        continue;
      }
      final state = _controller.childrenState(
        boundary.node.postNumber,
        depth: boundary.childDepth,
      );
      if (state.loading || state.error != null) continue;
      final box = _boundaryKeys[(boundary.node.postNumber, boundary.childDepth)]
          ?.currentContext
          ?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.bottom >= bounds.top && rect.top <= bounds.bottom + prefetch) {
        unawaited(
          _loadChildren(boundary.node.postNumber, depth: boundary.childDepth),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleObservation();
    final projection = _displayedEntries(includeCollapsed: true);
    final entries = projection.entries;
    final rows = entries.whereType<NestedVisibleRow>().toList(growable: false);
    final logicalRows = rows
        .where(
          (row) => row.ancestorPostNumbers.every(
            (number) => !_controller.isCollapsed(number),
          ),
        )
        .toList(growable: false);
    final threadEnds = {
      for (var index = 0; index < logicalRows.length; index++)
        if (index == logicalRows.length - 1 ||
            logicalRows[index + 1].depth == 0)
          logicalRows[index].node.postId,
    };
    final boundaries = _displayedEntries().entries
        .whereType<NestedChildrenBoundary>()
        .where(
          (entry) =>
              !_usesMobileLayout ||
              entry.depth - projection.depthOffset < _phoneDepthLimit,
        )
        .toList(growable: false);
    return DScrollChromePagination(
      hasMore: _controller.hasMoreRoots || boundaries.isNotEmpty,
      loading:
          _controller.loadingMoreRoots ||
          boundaries.any(
            (entry) => _controller
                .childrenState(entry.node.postNumber, depth: entry.childDepth)
                .loading,
          ),
      child: PluginTopicHeader(
        reader: reader,
        bodyBuilder: (header) => NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _scheduleObservation();
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification is ScrollUpdateNotification &&
                  _restoring &&
                  !_applyingAnchorCorrection) {
                if (_scroll.position.hasUserMotion) {
                  _restoreMotionDelta += notification.scrollDelta ?? 0;
                } else {
                  _finishAnchorRestore();
                }
              }
              return false;
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ContentReadingLane(
                  builder: (context, lane) => DScrollBar(
                    controller: _scroll,
                    child: CustomScrollView(
                      key: _viewport,
                      controller: _scroll,
                      scrollCacheExtent: _pagingAnchorCacheExtent == null
                          ? null
                          : ScrollCacheExtent.pixels(_pagingAnchorCacheExtent!),
                      slivers: [
                        SliverToBoxAdapter(child: header.spacer),
                        SliverPadding(
                          padding: lane.padding,
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: _intro(context),
                                ),
                              ),
                              if (_controller.op case final op?)
                                if (!op.data.hiddenDeleted)
                                  SliverToBoxAdapter(
                                    child: _post(context, op, -1),
                                  ),
                              SliverList.builder(
                                itemCount: entries.length,
                                findChildIndexCallback: (key) {
                                  final index = entries.indexWhere(
                                    (entry) =>
                                        key ==
                                        (entry is NestedVisibleRow
                                            ? ValueKey(entry.node.postId)
                                            : ValueKey((
                                                'nested-boundary',
                                                entry.node.postId,
                                              ))),
                                  );
                                  return index < 0 ? null : index;
                                },
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  if (entry is NestedChildrenBoundary) {
                                    return KeyedSubtree(
                                      key: ValueKey((
                                        'nested-boundary',
                                        entry.node.postId,
                                      )),
                                      child: _childrenBoundary(
                                        context,
                                        entry,
                                        projection.depthOffset,
                                      ),
                                    );
                                  }
                                  if (entry is NestedThreadContinuation) {
                                    return KeyedSubtree(
                                      key: ValueKey((
                                        'nested-boundary',
                                        entry.node.postId,
                                      )),
                                      child: DCollapsible(
                                        open: entry.ancestorPostNumbers.every(
                                          (number) =>
                                              !_controller.isCollapsed(number),
                                        ),
                                        child: DCollapsibleContent(
                                          duration: DMotion.change,
                                          child: DButton(
                                            variant: DButtonVariant.inline,
                                            size: DButtonSize.chip,
                                            label: Text(
                                              appL10n
                                                  .nestedRepliesContinueThread,
                                            ),
                                            onPressed: () => _navigate(
                                              target: entry.node.postNumber,
                                              context: 0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final row = entry as NestedVisibleRow;
                                  final post = _post(
                                    context,
                                    row.node,
                                    row.actualDepth,
                                    displayDepth:
                                        row.depth - projection.depthOffset,
                                    continuations: row.ancestorContinuations
                                        .skip(projection.depthOffset)
                                        .toList(growable: false),
                                    ancestors: row.ancestorPostNumbers
                                        .skip(projection.depthOffset)
                                        .toList(growable: false),
                                    endOfThread: threadEnds.contains(
                                      row.node.postId,
                                    ),
                                  );
                                  final presented = DCollapsible(
                                    open: row.ancestorPostNumbers.every(
                                      (number) =>
                                          !_controller.isCollapsed(number),
                                    ),
                                    child: DCollapsibleContent(
                                      duration: DMotion.change,
                                      child: post,
                                    ),
                                  );
                                  return KeyedSubtree(
                                    key: ValueKey(row.node.postId),
                                    child:
                                        _usesMobileLayout &&
                                            row != rows.first &&
                                            row.depth == 0
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const DSeparator(thickness: 6),
                                              presented,
                                            ],
                                          )
                                        : presented,
                                  );
                                },
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _footer(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.only(
                            bottom: TopicCornerControls.bottomClearanceOf(
                              context,
                              TopicCornerControls.heightOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TopicCornerControls(
                  height: TopicCornerControls.heightOf(context),
                  child: DReferenceTextScale(child: _sortControl(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
