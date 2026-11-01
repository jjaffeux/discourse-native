import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'post_voting_actions.dart';
import 'post_voting_controller.dart';
import 'post_voting_data.dart';
import 'post_voting_services.dart';
import 'post_voting_vote_controls.dart';

class PostVotingReader extends StatefulWidget {
  const PostVotingReader({
    super.key,
    required this.reader,
    required this.services,
  });
  final PluginTopicReader reader;
  final PostVotingServices services;
  @override
  State<PostVotingReader> createState() => _PostVotingReaderState();
}

class _PostVotingReaderState extends State<PostVotingReader> {
  late final PostVotingController _controller;
  late final ScrollController _scroll;
  final GlobalKey _viewport = GlobalKey(), _answers = GlobalKey();
  final Map<int, GlobalKey> _postKeys = {};
  Timer? _timing;
  bool _scheduled = false, _restoring = false;
  Set<int> _exposed = {};
  PostVotingViewSnapshot? _restore;
  bool _initialTargetResolved = false;
  PluginTopicReader get reader => widget.reader;
  @override
  void initState() {
    super.initState();
    _controller = PostVotingController(
      reader: reader,
      services: widget.services,
      beforeRefresh: () => _restore = _snapshot() ?? _restore,
    )..addListener(_changed);
    _restore = widget.services.memory(reader, _controller.order);
    _scroll = ScrollController(initialScrollOffset: _restore?.offset ?? 0)
      ..addListener(_scrolled);
    _timing = Timer.periodic(const Duration(seconds: 2), (_) => _observe());
    unawaited(_controller.initialize());
  }

  void _changed() {
    if (mounted) {
      setState(() {});
      _schedule();
    }
  }

  void _scrolled() {
    if (!_restoring) _remember();
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_controller.current) return;
      _restoreAnchor();
      _resolveInitialTarget();
      reader.setVisiblePostIds(
        _controller.visibleIds.where(
          (id) => reader.post(id)?.contentRedacted == false,
        ),
      );
      if (_scroll.hasClients &&
          _scroll.position.extentAfter < 220 &&
          _controller.hasMore &&
          !_controller.loading &&
          !_controller.loadingMore) {
        unawaited(_page());
      }
    });
  }

  List<({int id, int number, double top})> _visible() {
    final view = _viewport.currentContext?.findRenderObject();
    if (view is! RenderBox || !view.hasSize) return const [];
    final bounds = view.localToGlobal(Offset.zero) & view.size;
    final visible = <({int id, int number, double top})>[];
    for (final id in _controller.visibleIds) {
      final box = _postKeys[id]?.currentContext?.findRenderObject();
      final post = reader.post(id);
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          post == null ||
          post.contentRedacted ||
          post.isDeleted) {
        continue;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (bounds.intersect(rect).height >= math.min(64, rect.height / 2)) {
        visible.add((
          id: id,
          number: post.postNumber,
          top: rect.top - bounds.top,
        ));
      }
    }
    visible.sort((a, b) => a.top.compareTo(b.top));
    return visible;
  }

  void _observe() {
    if (!_controller.current || !reader.foreground) {
      _exposed.clear();
      return;
    }
    final visible = _visible().map((item) => item.number).toSet();
    final seen = visible.intersection(_exposed);
    _exposed = visible;
    if (seen.isNotEmpty) unawaited(reader.observeVisible(seen));
  }

  PostVotingViewSnapshot? _snapshot() {
    if (!_scroll.hasClients || !_controller.current) return null;
    final first = _visible().firstOrNull;
    return PostVotingViewSnapshot(
      ids: _controller.orderedIds,
      loadedIds: _controller.loadedIds,
      order: _controller.order,
      offset: _scroll.offset,
      anchorId: first?.id,
      anchorOffset: first?.top ?? 0,
    );
  }

  void _remember() {
    final value = _snapshot();
    if (value != null) widget.services.remember(reader, value);
  }

  Future<void> _refresh() async {
    _restore = _snapshot();
    await _controller.refresh();
    _schedule();
  }

  Future<void> _page({bool earlier = false}) async {
    if (_controller.loading || _controller.loadingMore) return;
    _restore = _snapshot();
    await _controller.loadMore(earlier: earlier);
    _schedule();
  }

  void _restoreAnchor() {
    final saved = _restore;
    if (saved == null ||
        _controller.loading ||
        _controller.loadingMore ||
        !_scroll.hasClients) {
      return;
    }
    var id = saved.anchorId;
    if (id != null && !_controller.visibleIds.contains(id)) {
      final oldIndex = saved.ids.indexOf(id);
      id = saved.ids
          .skip(oldIndex < 0 ? 0 : oldIndex)
          .where(_controller.visibleIds.contains)
          .firstOrNull;
    }
    final box = _postKeys[id]?.currentContext?.findRenderObject();
    final viewport = _viewport.currentContext?.findRenderObject();
    if (box is RenderBox &&
        box.hasSize &&
        viewport is RenderBox &&
        viewport.hasSize) {
      final top =
          box.localToGlobal(Offset.zero).dy -
          viewport.localToGlobal(Offset.zero).dy;
      final offset = (_scroll.offset + top - saved.anchorOffset).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _restoring = true;
      try {
        if ((offset - _scroll.offset).abs() > .5) _scroll.jumpTo(offset);
      } finally {
        _restoring = false;
      }
    }
    _restore = null;
  }

  void _resolveInitialTarget() {
    if (_initialTargetResolved || _controller.loading) return;
    final target = _controller.nearPostNumber;
    if (target == null || target <= 1) {
      _initialTargetResolved = true;
      return;
    }
    final id = _controller.visibleIds
        .where((id) => reader.post(id)?.postNumber == target)
        .firstOrNull;
    final context = _postKeys[id]?.currentContext;
    _initialTargetResolved = true;
    if (context != null) {
      unawaited(Scrollable.ensureVisible(context, alignment: .1));
    }
  }

  Future<void> _order(PostVotingOrder order) async {
    _remember();
    _restore = null;
    _exposed.clear();
    await _controller.changeOrder(order);
    if (!mounted || !_controller.current) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _answers.currentContext;
      if (mounted && context != null) {
        unawaited(Scrollable.ensureVisible(context, alignment: .05));
      }
    });
  }

  Widget _post(int id) {
    final post = reader.post(id);
    if (post == null) return const SizedBox.shrink();
    final likes =
        post.postNumber == 1 ||
        widget.services.settingsFor(reader.siteUrl).answerLikesEnabled;
    return KeyedSubtree(
      key: _postKeys.putIfAbsent(id, GlobalKey.new),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!post.isSmallAction)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: PostVotingVoteControls(
                reader: reader,
                postId: id,
                services: widget.services,
              ),
            ),
          Expanded(
            child: PluginTopicPost(
              reader: reader,
              postId: id,
              enableDoubleTapReaction: likes,
            ),
          ),
        ],
      ),
    );
  }

  Widget _answerControls(BuildContext context) {
    final count =
        reader.topic?.plugins.get(postVotingTopicKey)?.answerCount ??
        _controller.answerIds
            .where((id) => reader.post(id)?.postType == Post.regularPostType)
            .length;
    return Padding(
      key: _answers,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DLabel(child: Text(context.l10n.postVotingAnswerCount(count))),
          DToggleGroup<PostVotingOrder>(
            key: const ValueKey('post-voting-order'),
            values: [_controller.order],
            allowEmptySelection: false,
            density: DToggleDensity.postReaction,
            size: DControlSize.regular,
            spacing: .5,
            scrollable: false,
            semanticLabel: context.l10n.sort,
            items: [
              DToggleGroupItem(
                value: PostVotingOrder.votes,
                child: Text(context.l10n.postVotingVotes),
              ),
              DToggleGroupItem(
                value: PostVotingOrder.activity,
                child: Text(context.l10n.activity),
              ),
            ],
            onChanged: _controller.loading
                ? null
                : (values) => unawaited(_order(values.single)),
          ),
          if (reader.topic?.canCreatePost == true)
            DButton(
              key: const ValueKey('post-voting-answer'),
              label: Text(context.l10n.answer),
              icon: const DIcon(DIcons.reply),
              onPressed:
                  reader.topic?.closed == true || reader.topic?.archived == true
                  ? null
                  : () => reader.reply(),
            ),
          if (_controller.rankDirty)
            DButton(
              variant: DButtonVariant.ghost,
              label: Text(context.l10n.postVotingRefreshAnswers),
              icon: const DIcon(DIcons.arrowRotateRight),
              onPressed: _controller.loading ? null : _refresh,
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _remember();
    _timing?.cancel();
    _controller.removeListener(_changed);
    _controller.dispose();
    _scroll.removeListener(_scrolled);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.current) return const SizedBox.shrink();
    _schedule();
    final question = _controller.questionId;
    final count =
        reader.topic?.plugins.get(postVotingTopicKey)?.answerCount ??
        _controller.answerIds.length;
    return DScrollChromePagination(
      hasMore: _controller.hasMore,
      loading: _controller.loadingMore,
      child: PluginTopicHeader(
        reader: reader,
        bodyBuilder: (header) => ContentReadingLane(
          builder: (context, lane) => DScrollBar(
            controller: _scroll,
            child: SingleChildScrollView(
              key: _viewport,
              controller: _scroll,
              padding: lane.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header.spacer,
                  if (reader.topic?.closed == true ||
                      reader.topic?.archived == true)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: DAlert(
                        description: DAlertDescription(
                          child: Text(context.l10n.postVotingClosed),
                        ),
                      ),
                    ),
                  if (_controller.loading && _controller.visibleIds.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: DSpinner()),
                    ),
                  if (question != null) _post(question),
                  if (count > 0) _answerControls(context),
                  if (_controller.hasEarlier)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: DButton(
                        variant: DButtonVariant.ghost,
                        label: Text(context.l10n.postVotingLoadEarlier),
                        loading: _controller.loadingMore,
                        onPressed:
                            _controller.loadingMore || _controller.loading
                            ? null
                            : () => unawaited(_page(earlier: true)),
                      ),
                    ),
                  for (final id in _controller.answerIds) _post(id),
                  if (_controller.error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: DAlert(
                        variant: DAlertVariant.destructive,
                        description: DAlertDescription(
                          child: Text(postVotingError(_controller.error!)),
                        ),
                        action: DAlertAction(
                          child: DButton(
                            label: Text(context.l10n.retry),
                            onPressed: _refresh,
                          ),
                        ),
                      ),
                    ),
                  if (_controller.loading &&
                          _controller.visibleIds.isNotEmpty ||
                      _controller.loadingMore)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: DSpinner()),
                    ),
                  if (_controller.hasMore && !_controller.loadingMore)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: DButton(
                        variant: DButtonVariant.ghost,
                        label: Text(context.l10n.loadMore),
                        onPressed: _controller.loading
                            ? null
                            : () => unawaited(_page()),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
