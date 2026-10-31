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
  late final ScrollController _scroll;
  final GlobalKey _viewport = GlobalKey();
  final Map<int, GlobalKey> _postKeys = {};
  final Map<int, FocusNode> _collapseFocus = {};
  final Map<int, String> _revealed = {};
  final Set<int> _revealing = {};
  final Map<int, Object> _revealErrors = {};
  final Set<int> _liveReads = {};
  StreamSubscription<Object?>? _events;
  Timer? _timing;
  Timer? _refresh;
  Timer? _rememberTimer;
  late final Object _memoryKey;
  _RememberedReader? _restore;
  bool _restoring = true;
  bool _scheduled = false;
  bool _saveGraphAfterFrame = false;
  late bool _wasForeground;
  Set<int> _timingCandidates = {};
  int _memoryRevision = 0;

  PluginTopicReader get reader => widget.reader;

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
    _memoryKey = (
      reader.siteUrl,
      reader.tabId,
      reader.topicId,
      sort,
      target,
      context,
      query['collapse_replies'],
      widget.settings.maxDepth,
      widget.settings.capDepth,
    );
    _restore = widget.memory?._take(_memoryKey);
    _scroll = ScrollController(initialScrollOffset: _restore?.offset ?? 0)
      ..addListener(_onScroll);
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
      _observe();
      _restoreAnchor();
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
    _controller.setCollapsed(postNumber, collapsed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = _collapseFocus[postNumber];
      if (focus?.context != null) focus!.requestFocus();
    });
  }

  List<({int number, int id, double top})> _visible() {
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return const [];
    }
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    final visible = <({int number, int id, double top})>[];
    for (final entry in _postKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      final post = reader.post(entry.key);
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          post == null ||
          post.contentRedacted) {
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

  void _observe({bool timing = false}) {
    if (!reader.foreground) return;
    final visible = _visible();
    reader.setVisiblePostIds([
      if (_controller.op case final op?) op.postId,
      ..._displayedRows().rows.map((row) => row.node.postId),
    ]);
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
    final visible = _visible();
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
    _restoring = true;
  }

  Future<void> _reload() async {
    await _controller.reload(beforeApply: _prepareAnchorRestore);
    if (mounted && reader.isCurrent) _scheduleObservation();
  }

  void _restoreAnchor() {
    if (!_restoring ||
        _controller.loading ||
        _controller.restoringPages ||
        !_scroll.hasClients) {
      return;
    }
    final saved = _restore;
    if (saved != null && saved.anchor != null) {
      final visible = _visible()
          .where((post) => post.id == saved.anchor)
          .firstOrNull;
      if (visible != null) {
        final destination =
            (_scroll.offset + visible.top - (saved.anchorOffset ?? 0)).clamp(
              0.0,
              _scroll.position.maxScrollExtent,
            );
        if ((destination - _scroll.offset).abs() > 1) {
          _scroll.jumpTo(destination);
        }
      }
    }
    _restoring = false;
    _restore = null;
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
        final json = await widget.api.transport.pluginGetJson(
          siteUrl: reader.siteUrl,
          path: '/posts/$id.json',
          apiKey: request.apiKey,
          clientId: request.clientId,
        );
        final number = nestedPositiveInt(json['post_number']);
        if (nestedPositiveInt(json['topic_id']) != reader.topicId ||
            nestedPositiveInt(json['id']) != id ||
            number == null) {
          throw const FormatException('Post belongs to another topic');
        }
        // The tree endpoint applies ignored/deleted visibility. A normal post
        // lookup supplies identity only and must not publish its unfiltered body.
        final page = await widget.api.context(
          siteUrl: reader.siteUrl,
          topicId: reader.topicId,
          slug: reader.route.slug ?? 'topic',
          credentials: request,
          sort: _controller.effectiveSort,
          postNumber: number,
          contextDepth: 0,
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

  int get _phoneDepthLimit =>
      math.max(1, ((MediaQuery.sizeOf(context).width - 250) / 20).floor());

  ({List<NestedVisibleRow> rows, int depthOffset}) _displayedRows() {
    var rows = _controller.visibleRows();
    var baseDepth = 0;
    if (MediaQuery.sizeOf(context).width < 600 && _controller.contextMode) {
      final target = rows.indexWhere(
        (row) => row.node.postNumber == _controller.targetPostNumber,
      );
      if (target >= 0) {
        baseDepth = rows[target].depth;
        rows = rows.sublist(target);
      }
    }
    return (
      rows: [
        for (final row in rows)
          if (MediaQuery.sizeOf(context).width >= 600 ||
              row.depth - baseDepth <= _phoneDepthLimit)
            row,
      ],
      depthOffset: baseDepth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final projection = _displayedRows();
    final rows = projection.rows;
    return PluginTopicHeader(
      reader: reader,
      bodyBuilder: (header) => NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction != ScrollDirection.idle) {
            _restoring = false;
            _restore = null;
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
                            SliverToBoxAdapter(child: _post(context, op, -1)),
                          SliverList.builder(
                            itemCount: rows.length,
                            findChildIndexCallback: (key) {
                              if (key is! ValueKey<int>) return null;
                              final index = rows.indexWhere(
                                (row) => row.node.postId == key.value,
                              );
                              return index < 0 ? null : index;
                            },
                            itemBuilder: (context, index) => KeyedSubtree(
                              key: ValueKey(rows[index].node.postId),
                              child: _post(
                                context,
                                rows[index].node,
                                rows[index].depth,
                                displayDepth:
                                    rows[index].depth - projection.depthOffset,
                                continuations: rows[index].ancestorContinuations
                                    .skip(projection.depthOffset)
                                    .toList(growable: false),
                                ancestors: rows[index].ancestorPostNumbers
                                    .skip(projection.depthOffset)
                                    .toList(growable: false),
                                endOfThread:
                                    index == rows.length - 1 ||
                                    rows[index + 1].depth == 0,
                              ),
                            ),
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
    );
  }
}
