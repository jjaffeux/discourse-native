import 'package:flutter/foundation.dart';

import 'nested_replies_data.dart';

final class NestedPageReceipt<T> {
  NestedPageReceipt({
    required this.value,
    required Iterable<int> acceptedPostIds,
  }) : acceptedPostIds = Set.unmodifiable(acceptedPostIds);
  final T value;
  final Set<int> acceptedPostIds;
}

abstract interface class NestedRepliesLoader {
  bool get isCurrent;

  Future<NestedPageReceipt<NestedRootPage>?> roots({
    required NestedRepliesSort sort,
    required int page,
    required bool trackVisit,
  });

  Future<NestedPageReceipt<NestedContextPage>?> context({
    required NestedRepliesSort sort,
    required int postNumber,
    required int? contextDepth,
    required bool trackVisit,
  });

  Future<NestedPageReceipt<NestedChildrenPage>?> children({
    required NestedRepliesSort sort,
    required int parentPostNumber,
    required int depth,
    required int page,
  });
}

abstract interface class NestedRepliesScopedLoader {
  NestedRepliesLoader scoped(bool Function() current);
}

final class NestedChildrenState {
  const NestedChildrenState({
    this.page,
    this.hasMore = true,
    this.loading = false,
    this.error,
  });

  final int? page;
  final bool hasMore;
  final bool loading;
  final Object? error;
  bool get fetchedFromServer => page != null;
}

final class NestedVisibleRow {
  const NestedVisibleRow({
    required this.node,
    required this.depth,
    this.displayParentPostNumber,
    this.ancestorContinuations = const [],
    this.ancestorPostNumbers = const [],
  });

  final NestedReplyNode node;
  final int depth;
  final int? displayParentPostNumber;
  final List<bool> ancestorContinuations;
  final List<int> ancestorPostNumbers;
}

final class NestedRepliesSnapshot {
  NestedRepliesSnapshot._(NestedRepliesController controller)
    : nodes = Map.unmodifiable(controller._nodes),
      children = Map.unmodifiable({
        for (final entry in controller._children.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      }),
      childPages = Map.unmodifiable({
        for (final entry in controller._childPages.entries)
          entry.key: NestedChildrenState(
            page: entry.value.page,
            hasMore: entry.value.hasMore,
          ),
      }),
      collapsed = Set.unmodifiable(controller._collapsed),
      expanded = Set.unmodifiable(controller._expanded),
      roots = List.unmodifiable(controller._rootIds),
      ancestors = List.unmodifiable(controller._ancestorIds),
      pendingRoots = List.unmodifiable(controller._pendingRootIds),
      siblings = Map.unmodifiable({
        for (final entry in controller._siblings.entries)
          entry.key: List<int>.unmodifiable(entry.value),
      }),
      opId = controller._opId,
      targetId = controller._targetId,
      requestedSort = controller.requestedSort,
      effectiveSort = controller.effectiveSort,
      rootPage = controller.rootPage,
      hasMoreRoots = controller.hasMoreRoots,
      targetPostNumber = controller.targetPostNumber,
      contextDepth = controller.contextDepth,
      collapseReplies = controller.collapseReplies,
      ancestorsTruncated = controller.ancestorsTruncated,
      messageBusLastId = controller.messageBusLastId,
      pinnedPostIds = List.unmodifiable(controller.pinnedPostIds);

  final Map<int, NestedReplyNode> nodes;
  final Map<int, List<int>> children;
  final Map<(int, int), NestedChildrenState> childPages;
  final Set<int> collapsed;
  final Set<int> expanded;
  final List<int> roots;
  final List<int> ancestors;
  final List<int> pendingRoots;
  final Map<int, List<int>> siblings;
  final int? opId;
  final int? targetId;
  final NestedRepliesSort requestedSort;
  final NestedRepliesSort effectiveSort;
  final int rootPage;
  final bool hasMoreRoots;
  final int? targetPostNumber;
  final int? contextDepth;
  final bool collapseReplies;
  final bool ancestorsTruncated;
  final int? messageBusLastId;
  final List<int> pinnedPostIds;
  int get nodeCount => nodes.length;
}

final class NestedRepliesController extends ChangeNotifier {
  NestedRepliesController({
    required NestedRepliesLoader loader,
    NestedRepliesSettings settings = const NestedRepliesSettings(),
  }) : this._(loader: loader, settings: settings);

  NestedRepliesController._({
    required this.loader,
    required this.settings,
    this._current,
  }) : requestedSort = settings.defaultSort,
       effectiveSort = settings.defaultSort;

  final bool Function()? _current;
  final NestedRepliesLoader loader;
  final NestedRepliesSettings settings;
  final Map<int, NestedReplyNode> _nodes = {};
  final Map<int, int> _postNumberToId = {};
  final Map<int, List<int>> _children = {};
  final Map<(int, int), NestedChildrenState> _childPages = {};
  final Set<int> _collapsed = {};
  final Set<int> _expanded = {};
  final Map<int, ({NestedReplyNode root, bool own})> _openingRoots = {};
  NestedRepliesSnapshot? _snapshot;
  bool restoringPages = false;
  Object? _restoringOperation;
  final List<int> _rootIds = [];
  final List<int> _ancestorIds = [];
  final List<int> _pendingRootIds = [];
  final Map<int, List<int>> _siblings = {};
  int? _opId;
  int? _targetId;
  int _generation = 0;
  bool _disposed = false;

  NestedRepliesSort requestedSort;
  NestedRepliesSort effectiveSort;
  int rootPage = 0;
  bool hasMoreRoots = false;
  bool loading = false;
  bool loadingMoreRoots = false;
  Object? error;
  Object? rootPageError;
  int? targetPostNumber;
  int? contextDepth;
  bool collapseReplies = false;
  bool ancestorsTruncated = false;
  int? messageBusLastId;
  List<int> pinnedPostIds = const [];
  Map<String, dynamic>? topicMetadata;
  Map<String, dynamic>? recommendations;

  bool get isCurrent =>
      !_disposed && loader.isCurrent && (_current?.call() ?? true);
  bool get contextMode => targetPostNumber != null && targetPostNumber! > 1;
  NestedReplyNode? get op => _nodes[_opId];
  NestedReplyNode? get target => _nodes[_targetId];
  List<NestedReplyNode> get roots => _resolved(_rootIds);
  List<NestedReplyNode> get ancestors => _resolved(_ancestorIds);
  List<NestedReplyNode> get pendingRoots => _resolved(_pendingRootIds);
  Map<int, List<NestedReplyNode>> get siblings => Map.unmodifiable({
    for (final entry in _siblings.entries) entry.key: _resolved(entry.value),
  });
  Set<int> get collapsedPostNumbers => Set.unmodifiable(_collapsed);

  NestedReplyNode? post(int postId) => _nodes[postId];
  NestedReplyNode? postNumber(int number) => _nodes[_postNumberToId[number]];
  List<NestedReplyNode> childrenFor(int parentPostNumber) =>
      _resolved(_children[parentPostNumber] ?? const []);
  NestedChildrenState childrenState(
    int parentPostNumber, {
    required int depth,
  }) => _childPages[(parentPostNumber, depth)] ?? const NestedChildrenState();

  bool isCollapsed(int postNumber) => _collapsed.contains(postNumber);

  bool isExpanded(int postNumber, {required int depth}) {
    if (_expanded.contains(postNumber)) return true;
    if (collapseReplies) {
      if (!contextMode) return depth < 0;
      final targetDepth = _ancestorIds.length;
      return depth <= targetDepth;
    }
    final node = this.postNumber(postNumber);
    return childrenFor(postNumber).isNotEmpty ||
        (node != null && node.data.placeholder != NestedPostPlaceholder.none);
  }

  Future<void> open({
    int? postNumber,
    int? context,
    NestedRepliesSort? sort,
    bool collapse = false,
    bool foreground = true,
  }) async {
    if (!isCurrent) return;
    if (postNumber != null && postNumber <= 0) {
      throw ArgumentError.value(postNumber, 'postNumber');
    }
    if (context != null && (context < 0 || context > 100)) {
      throw ArgumentError.value(context, 'context');
    }
    final generation = ++_generation;
    targetPostNumber = postNumber;
    contextDepth = context;
    collapseReplies = collapse;
    requestedSort = sort ?? requestedSort;
    effectiveSort = requestedSort;
    loading = true;
    loadingMoreRoots = false;
    error = null;
    rootPageError = null;
    _childPages.clear();
    _openingRoots.clear();
    notifyListeners();
    try {
      if (contextMode) {
        final receipt = await _requestLoader(generation).context(
          sort: requestedSort,
          postNumber: postNumber!,
          contextDepth: context,
          trackVisit: foreground,
        );
        if (!_accepts(generation) || receipt == null) return;
        final page = receipt.value;
        _clearGraph();
        _install(page.posts.map((value) => value.post.id).toSet(), [
          if (page.op != null) page.op!,
          ...page.ancestors,
          page.target,
          ...page.siblings.values.expand((value) => value),
        ], receipt.acceptedPostIds);
        _opId = _accepted(page.op, receipt.acceptedPostIds);
        _targetId = _accepted(page.target, receipt.acceptedPostIds);
        _ancestorIds.addAll(
          _acceptedIds(page.ancestors, receipt.acceptedPostIds),
        );
        if (_targetId != null) {
          _rootIds.add(_ancestorIds.firstOrNull ?? _targetId!);
          for (var i = 0; i < _ancestorIds.length; i++) {
            final parent = _nodes[_ancestorIds[i]]!;
            _children[parent.postNumber] = [
              if (i + 1 < _ancestorIds.length)
                _ancestorIds[i + 1]
              else
                _targetId!,
            ];
            _expanded.add(parent.postNumber);
          }
        }
        for (final entry in page.siblings.entries) {
          _siblings[entry.key] = _acceptedIds(
            entry.value,
            receipt.acceptedPostIds,
          );
        }
        ancestorsTruncated = page.ancestorsTruncated;
        effectiveSort = page.effectiveSort;
        messageBusLastId = page.messageBusLastId;
        topicMetadata = page.topicMetadata;
        recommendations = page.recommendations;
        hasMoreRoots = false;
        rootPage = 0;
        pinnedPostIds = const [];
      } else {
        final receipt = await _requestLoader(
          generation,
        ).roots(sort: requestedSort, page: 0, trackVisit: foreground);
        if (!_accepts(generation) || receipt == null) return;
        final page = receipt.value;
        _clearGraph();
        _install(page.posts.map((value) => value.post.id).toSet(), [
          if (page.op != null) page.op!,
          ...page.roots,
        ], receipt.acceptedPostIds);
        _opId = _accepted(page.op, receipt.acceptedPostIds);
        _rootIds.addAll(_acceptedIds(page.roots, receipt.acceptedPostIds));
        rootPage = page.page;
        hasMoreRoots = page.hasMore;
        effectiveSort =
            page.effectiveSort ?? page.requestedSort ?? requestedSort;
        messageBusLastId = page.messageBusLastId;
        topicMetadata = page.topicMetadata;
        recommendations = page.recommendations;
        pinnedPostIds = page.pinnedPostIds;
        ancestorsTruncated = false;
      }
    } catch (failure) {
      if (_accepts(generation)) error = failure;
    } finally {
      if (_accepts(generation)) {
        loading = false;
        if (error == null) {
          final arrivals = _openingRoots.values.toList(growable: false);
          _openingRoots.clear();
          for (final arrival in arrivals) {
            queueRoot(arrival.root, own: arrival.own);
          }
        }
        notifyListeners();
      }
    }
  }

  Future<void> changeSort(NestedRepliesSort sort, {bool foreground = true}) =>
      open(
        postNumber: targetPostNumber,
        context: contextDepth,
        sort: sort,
        collapse: collapseReplies,
        foreground: foreground,
      );

  Future<void> loadMoreRoots() async {
    if (!isCurrent ||
        loading ||
        restoringPages ||
        loadingMoreRoots ||
        !hasMoreRoots ||
        contextMode) {
      return;
    }
    final generation = _generation;
    final pageNumber = rootPage + 1;
    loadingMoreRoots = true;
    rootPageError = null;
    notifyListeners();
    try {
      final receipt = await _requestLoader(
        generation,
      ).roots(sort: effectiveSort, page: pageNumber, trackVisit: false);
      if (!_accepts(generation) || receipt == null) return;
      final page = receipt.value;
      _install(
        page.posts.map((value) => value.post.id).toSet(),
        page.roots,
        receipt.acceptedPostIds,
      );
      _appendUnique(
        _rootIds,
        _acceptedIds(page.roots, receipt.acceptedPostIds),
      );
      rootPage = page.page;
      hasMoreRoots = page.hasMore;
      if (page.recommendations != null) recommendations = page.recommendations;
    } catch (failure) {
      if (_accepts(generation)) rootPageError = failure;
    } finally {
      if (_accepts(generation)) {
        loadingMoreRoots = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadChildren(int parentPostNumber, {required int depth}) async {
    if (!isCurrent ||
        loading ||
        restoringPages ||
        postNumber(parentPostNumber) == null) {
      return;
    }
    final key = (parentPostNumber, depth);
    final held = _childPages[key] ?? const NestedChildrenState();
    if (held.loading || !held.hasMore) return;
    final generation = _generation;
    final pageNumber = held.page == null ? 0 : held.page! + 1;
    _childPages[key] = NestedChildrenState(
      page: held.page,
      hasMore: held.hasMore,
      loading: true,
    );
    notifyListeners();
    try {
      final receipt = await _requestLoader(generation).children(
        sort: effectiveSort,
        parentPostNumber: parentPostNumber,
        depth: depth,
        page: pageNumber,
      );
      if (!_accepts(generation) || receipt == null) return;
      final page = receipt.value;
      _install(
        page.posts.map((value) => value.post.id).toSet(),
        page.children,
        receipt.acceptedPostIds,
      );
      final children = _children.putIfAbsent(parentPostNumber, () => []);
      _appendUnique(
        children,
        _acceptedIds(page.children, receipt.acceptedPostIds),
      );
      _childPages[key] = NestedChildrenState(
        page: page.page,
        hasMore: page.hasMore,
      );
      _expanded.add(parentPostNumber);
    } catch (failure) {
      if (_accepts(generation)) {
        _childPages[key] = NestedChildrenState(
          page: held.page,
          hasMore: held.hasMore,
          error: failure,
        );
      }
    } finally {
      if (_accepts(generation)) {
        final state = _childPages[key]!;
        if (state.loading) {
          _childPages[key] = NestedChildrenState(
            page: state.page,
            hasMore: state.hasMore,
            error: state.error,
          );
        }
        notifyListeners();
      }
    }
  }

  void setCollapsed(int postNumber, bool collapsed) {
    if (!isCurrent || this.postNumber(postNumber) == null) return;
    if (collapsed) {
      _collapsed.add(postNumber);
    } else {
      _collapsed.remove(postNumber);
    }
    notifyListeners();
  }

  void queueRoot(NestedReplyNode root, {required bool own}) {
    if (!isCurrent || contextMode) return;
    if (loading || restoringPages) {
      _openingRoots[root.postId] = (root: root, own: own);
      if (loading) return;
    }
    if (_nodes.containsKey(root.postId)) return;
    _install({root.postId}, [root], {root.postId});
    if (own) {
      _rootIds.insert(0, root.postId);
    } else if (!_pendingRootIds.contains(root.postId)) {
      _pendingRootIds.add(root.postId);
    }
    notifyListeners();
  }

  void showPendingRoots() {
    if (!isCurrent || _pendingRootIds.isEmpty) return;
    _rootIds.insertAll(
      0,
      _pendingRootIds.where((id) => !_rootIds.contains(id)),
    );
    _pendingRootIds.clear();
    notifyListeners();
  }

  void updatePins(Iterable<int> ids) {
    if (!isCurrent) return;
    pinnedPostIds = List.unmodifiable(ids.toSet());
    final promoted = [
      for (final id in pinnedPostIds)
        if (_rootIds.contains(id)) id,
    ];
    _rootIds.removeWhere(promoted.contains);
    _rootIds.insertAll(0, promoted);
    notifyListeners();
  }

  List<NestedVisibleRow> visibleRows({bool includeCollapsed = false}) {
    final rows = <NestedVisibleRow>[];
    final activePath = <int>{};
    void visit(
      int id,
      int depth,
      int? displayParent,
      List<bool> continuations,
      List<int> ancestors,
    ) {
      final node = _nodes[id];
      if (node == null || !activePath.add(id)) return;
      rows.add(
        NestedVisibleRow(
          node: node,
          depth: depth,
          displayParentPostNumber: displayParent,
          ancestorContinuations: continuations,
          ancestorPostNumbers: ancestors,
        ),
      );
      if ((includeCollapsed || !isCollapsed(node.postNumber)) &&
          isExpanded(node.postNumber, depth: depth)) {
        final children = _children[node.postNumber] ?? const <int>[];
        for (var index = 0; index < children.length; index++) {
          visit(
            children[index],
            depth + 1,
            node.postNumber,
            List.unmodifiable([...continuations, index < children.length - 1]),
            List.unmodifiable([...ancestors, node.postNumber]),
          );
        }
      }
      activePath.remove(id);
    }

    for (final id in _rootIds) {
      visit(id, 0, null, const [], const []);
    }
    return List.unmodifiable(rows);
  }

  void _install(
    Set<int> payloadIds,
    Iterable<NestedReplyNode> nodes,
    Set<int> accepted,
  ) {
    for (final node in nodes) {
      if (!accepted.contains(node.postId) ||
          !payloadIds.contains(node.postId)) {
        continue;
      }
      final held = _nodes[node.postId];
      _nodes[node.postId] = node;
      _postNumberToId[node.postNumber] = node.postId;
      final children = _children.putIfAbsent(node.postNumber, () => []);
      _appendUnique(children, _acceptedIds(node.children, accepted));
      _install(payloadIds, node.children, accepted);
      if (held != null && node.children.isEmpty) {
        _nodes[node.postId] = node.withChildren(held.children);
      }
    }
  }

  List<NestedReplyNode> _resolved(Iterable<int> ids) => List.unmodifiable([
    for (final id in ids)
      if (_nodes[id] != null) _nodes[id]!,
  ]);

  static int? _accepted(NestedReplyNode? node, Set<int> accepted) =>
      node != null && accepted.contains(node.postId) ? node.postId : null;
  static List<int> _acceptedIds(
    Iterable<NestedReplyNode> nodes,
    Set<int> accepted,
  ) => [
    for (final node in nodes)
      if (accepted.contains(node.postId)) node.postId,
  ];
  static void _appendUnique(List<int> destination, Iterable<int> incoming) {
    for (final id in incoming) {
      if (!destination.contains(id)) destination.add(id);
    }
  }

  NestedRepliesLoader _requestLoader(int generation) => switch (loader) {
    final NestedRepliesScopedLoader scoped => scoped.scoped(
      () => _accepts(generation),
    ),
    _ => loader,
  };

  bool _accepts(int generation) => isCurrent && generation == _generation;

  void _clearGraph() {
    _nodes.clear();
    _postNumberToId.clear();
    _children.clear();
    _rootIds.clear();
    _ancestorIds.clear();
    _pendingRootIds.clear();
    _siblings.clear();
    _opId = null;
    _targetId = null;
  }

  NestedRepliesSnapshot snapshot() =>
      _snapshot ??= NestedRepliesSnapshot._(this);

  void restore(NestedRepliesSnapshot snapshot) {
    if (!isCurrent) return;
    ++_generation;
    _clearGraph();
    _nodes.addAll(snapshot.nodes);
    _postNumberToId.addAll({
      for (final node in snapshot.nodes.values) node.postNumber: node.postId,
    });
    _children.addAll({
      for (final entry in snapshot.children.entries)
        entry.key: List.of(entry.value),
    });
    _childPages
      ..clear()
      ..addAll(snapshot.childPages);
    _collapsed
      ..clear()
      ..addAll(snapshot.collapsed);
    _expanded
      ..clear()
      ..addAll(snapshot.expanded);
    _rootIds.addAll(snapshot.roots);
    _ancestorIds.addAll(snapshot.ancestors);
    _pendingRootIds.addAll(snapshot.pendingRoots);
    _siblings.addAll(snapshot.siblings);
    _opId = snapshot.opId;
    _targetId = snapshot.targetId;
    requestedSort = snapshot.requestedSort;
    effectiveSort = snapshot.effectiveSort;
    rootPage = snapshot.rootPage;
    hasMoreRoots = snapshot.hasMoreRoots;
    targetPostNumber = snapshot.targetPostNumber;
    contextDepth = snapshot.contextDepth;
    collapseReplies = snapshot.collapseReplies;
    ancestorsTruncated = snapshot.ancestorsTruncated;
    messageBusLastId = snapshot.messageBusLastId;
    pinnedPostIds = snapshot.pinnedPostIds;
    loading = false;
    loadingMoreRoots = false;
    error = null;
    rootPageError = null;
    notifyListeners();
  }

  Future<void> refreshVisit({VoidCallback? beforeApply}) => _reconcile(
    foreground: true,
    queueNewRoots: true,
    beforeApply: beforeApply,
  );

  Future<void> reload({VoidCallback? beforeApply}) =>
      _reconcile(foreground: false, beforeApply: beforeApply);

  Future<void> _reconcile({
    required bool foreground,
    bool queueNewRoots = false,
    VoidCallback? beforeApply,
  }) async {
    if (!isCurrent) return;
    final saved = snapshot();
    final generation = ++_generation;
    final operation = Object();
    _restoringOperation = operation;
    restoringPages = true;
    loading = false;
    loadingMoreRoots = false;
    error = null;
    rootPageError = null;
    for (final entry in _childPages.entries.toList()) {
      if (entry.value.loading) {
        _childPages[entry.key] = NestedChildrenState(
          page: entry.value.page,
          hasMore: entry.value.hasMore,
        );
      }
    }
    _openingRoots.clear();
    final refreshed = NestedRepliesController._(
      loader: loader,
      settings: settings,
      current: () => _accepts(generation),
    );
    notifyListeners();
    try {
      await refreshed.open(
        postNumber: saved.targetPostNumber,
        context: saved.contextDepth,
        sort: saved.requestedSort,
        collapse: saved.collapseReplies,
        foreground: foreground,
      );
      if (!_accepts(generation)) return;
      if (refreshed.error case final failure?) throw failure;
      while (refreshed.rootPage < saved.rootPage &&
          refreshed.hasMoreRoots &&
          !refreshed.contextMode) {
        await refreshed.loadMoreRoots();
        if (!_accepts(generation)) return;
        if (refreshed.rootPageError case final failure?) throw failure;
      }
      if (refreshed.hasMoreRoots) refreshed._retainTrailingRoots(saved);
      final pages = saved.childPages.entries.toList()
        ..sort((a, b) => a.key.$2.compareTo(b.key.$2));
      for (final entry in pages) {
        if (!_accepts(generation)) return;
        final expectedPage = entry.value.page;
        if (expectedPage == null ||
            refreshed.postNumber(entry.key.$1) == null) {
          continue;
        }
        refreshed._children[entry.key.$1] = [];
        for (var page = 0; page <= expectedPage; page++) {
          final state = refreshed.childrenState(
            entry.key.$1,
            depth: entry.key.$2,
          );
          if (!state.hasMore) break;
          await refreshed.loadChildren(entry.key.$1, depth: entry.key.$2);
          if (!_accepts(generation)) return;
          if (refreshed.childrenState(entry.key.$1, depth: entry.key.$2).error
              case final failure?) {
            throw failure;
          }
        }
      }
      if (!_accepts(generation)) return;
      beforeApply?.call();
      if (!_accepts(generation)) return;
      refreshed._collapsed.addAll(_collapsed);
      refreshed._expanded.addAll(_expanded);
      if (!refreshed.contextMode) {
        final pending = refreshed._rootIds
            .where(
              (id) =>
                  _pendingRootIds.contains(id) ||
                  (queueNewRoots && !_nodes.containsKey(id)),
            )
            .toList();
        refreshed._pendingRootIds.addAll(pending);
        refreshed._rootIds.removeWhere(pending.contains);
      }
      final arrivals = _openingRoots.values.toList(growable: false);
      _openingRoots.clear();
      final metadata = refreshed.topicMetadata;
      final related = refreshed.recommendations;
      restore(refreshed.snapshot());
      topicMetadata = metadata;
      recommendations = related;
      for (final arrival in arrivals) {
        queueRoot(arrival.root, own: arrival.own);
      }
    } catch (failure) {
      if (_accepts(generation)) error = failure;
    } finally {
      refreshed.dispose();
      if (isCurrent && identical(_restoringOperation, operation)) {
        _restoringOperation = null;
        restoringPages = false;
        _openingRoots.clear();
        notifyListeners();
      }
    }
  }

  void _retainTrailingRoots(NestedRepliesSnapshot saved) {
    void retain(int id) {
      if (_nodes.containsKey(id)) return;
      final node = saved.nodes[id];
      if (node == null) return;
      _nodes[id] = node;
      _postNumberToId[node.postNumber] = id;
      final children = saved.children[node.postNumber] ?? const <int>[];
      _children[node.postNumber] = [
        for (final child in children)
          if (!_nodes.containsKey(child)) child,
      ];
      for (final child in _children[node.postNumber]!) {
        retain(child);
      }
    }

    // A nonterminal window cannot prove that an old trailing root was removed.
    // A root already present elsewhere in the new graph has a known placement.
    for (final id in [...saved.roots, ...saved.pendingRoots]) {
      if (_nodes.containsKey(id)) continue;
      retain(id);
      if (_nodes.containsKey(id)) _rootIds.add(id);
    }
  }

  @override
  void notifyListeners() {
    _snapshot = null;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
