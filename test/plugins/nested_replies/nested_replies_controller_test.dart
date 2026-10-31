import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_controller.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rail projection follows displayed sibling branches and stops after collapse',
    () async {
      final loader = _Loader()
        ..rootHandler = (_) async => _roots([
          node(
            2,
            children: [
              node(3, parent: 2, children: [node(4, parent: 3)]),
              node(5, parent: 2, children: [node(6, parent: 2)]),
            ],
          ),
          node(7),
        ]);
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      final rows = controller.visibleRows();
      expect(rows.map((row) => row.node.postNumber), [2, 3, 4, 5, 6, 7]);
      expect(rows.map((row) => row.ancestorContinuations), [
        <bool>[],
        [true],
        [true, false],
        [false],
        [false, false],
        <bool>[],
      ]);
      expect(rows[4].displayParentPostNumber, 5);
      expect(rows[4].ancestorPostNumbers, [2, 5]);
      expect(rows[4].node.data.replyToPostNumber, 2);
      controller.setCollapsed(3, true);
      expect(controller.visibleRows().map((row) => row.node.postNumber), [
        2,
        3,
        5,
        6,
        7,
      ]);
      expect(
        controller
            .visibleRows(includeCollapsed: true)
            .map((row) => row.node.postNumber),
        [2, 3, 4, 5, 6, 7],
      );
      expect(
        controller.visibleRows(includeCollapsed: true)[2].ancestorPostNumbers,
        [2, 3],
      );
      controller.setCollapsed(2, true);
      expect(controller.visibleRows().map((row) => row.node.postNumber), [
        2,
        7,
      ]);
    },
  );

  test(
    'live roots received during the snapshot load survive and deduplicate',
    () async {
      final pending = Completer<NestedPageReceipt<NestedRootPage>?>();
      final loader = _Loader()..rootHandler = (_) => pending.future;
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      final opening = controller.open();
      controller.queueRoot(node(3), own: false);
      controller.queueRoot(node(4), own: true);
      controller.queueRoot(node(5), own: false);
      pending.complete(_roots([node(2), node(5)]));
      await opening;
      expect(controller.roots.map((node) => node.postNumber), [4, 2, 5]);
      expect(controller.pendingRoots.map((node) => node.postNumber), [3]);
      controller.showPendingRoots();
      expect(controller.roots.map((node) => node.postNumber), [3, 4, 2, 5]);
    },
  );

  test(
    'foreground visit queues roots missed while the reader was hidden',
    () async {
      final loader = _Loader()..rootHandler = (_) async => _roots([node(2)]);
      final original = NestedRepliesController(loader: loader);
      addTearDown(original.dispose);
      await original.open();
      final restored = NestedRepliesController(loader: loader);
      addTearDown(restored.dispose);
      restored.restore(original.snapshot());
      loader.rootHandler = (_) async {
        final roots = [node(3), node(2)];
        final op = node(1);
        final posts = [op, ...roots].map(_payload).toList();
        return NestedPageReceipt(
          value: NestedRootPage(
            roots: roots,
            op: op,
            posts: posts,
            page: 0,
            hasMore: false,
            pinnedPostIds: [103],
            messageBusLastId: 88,
          ),
          acceptedPostIds: posts.map((post) => post.post.id),
        );
      };
      await restored.refreshVisit();
      expect(restored.op!.postNumber, 1);
      expect(restored.pinnedPostIds, [103]);
      expect(restored.messageBusLastId, 88);
      expect(restored.roots.map((node) => node.postNumber), [2]);
      expect(restored.pendingRoots.map((node) => node.postNumber), [3]);
      restored.showPendingRoots();
      expect(restored.roots.map((node) => node.postNumber), [3, 2]);
      expect(loader.rootRequests.map((request) => request.trackVisit), [
        true,
        true,
      ]);
    },
  );

  test(
    'foreground revisit removes and relocates known branch references',
    () async {
      final loader = _Loader();
      loader.rootHandler = (_) async => _roots([
        node(2, children: [node(3, parent: 2), node(4, parent: 2)]),
        node(5),
      ]);
      loader.childHandler = (_) async =>
          _children([node(3, parent: 2), node(4, parent: 2)], hasMore: false);
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      await controller.loadChildren(2, depth: 1);
      controller.setCollapsed(2, true);
      controller.setCollapsed(5, true);
      loader.rootHandler = (_) async => _roots([
        node(2, children: [node(3, parent: 2)]),
        node(5, children: [node(4, parent: 5)]),
      ]);
      loader.childHandler = (_) async => _children([], hasMore: false);
      await controller.refreshVisit();
      expect(controller.roots.map((node) => node.postNumber), [2, 5]);
      expect(controller.visibleRows().map((row) => row.node.postNumber), [
        2,
        5,
      ]);
      expect(controller.childrenFor(2), isEmpty);
      expect(controller.childrenFor(5).single.postNumber, 4);
      expect(controller.postNumber(4)!.data.replyToPostNumber, 5);
      expect(controller.childrenState(2, depth: 1).page, 0);
      expect(controller.isCollapsed(2), isTrue);
      expect(controller.isCollapsed(5), isTrue);
    },
  );

  test(
    'foreground revisit swaps atomically and preserves roots arriving during replay',
    () async {
      final loader = _Loader()
        ..rootHandler = (request) async => _roots(
          [node(request.page == 0 ? 2 : 4)],
          page: request.page,
          hasMore: request.page == 0,
        );
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      await controller.loadMoreRoots();
      final pending = Completer<NestedPageReceipt<NestedRootPage>?>();
      loader.rootHandler = (request) => request.page == 0
          ? Future.value(_roots([node(3), node(2)], hasMore: true))
          : pending.future;
      var applied = false;
      final visiting = controller.refreshVisit(
        beforeApply: () => applied = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.roots.map((node) => node.postNumber), [2, 4]);
      expect(controller.loading, isFalse);
      expect(controller.restoringPages, isTrue);
      expect(applied, isFalse);
      controller.queueRoot(node(7), own: false);
      controller.queueRoot(node(8), own: true);
      controller.setCollapsed(2, true);
      pending.complete(_roots([node(4)], page: 1, hasMore: true));
      await visiting;
      expect(applied, isTrue);
      expect(controller.roots.map((node) => node.postNumber), [8, 2, 4]);
      expect(controller.pendingRoots.map((node) => node.postNumber), [3, 7]);
      expect(controller.isCollapsed(2), isTrue);
      expect(controller.restoringPages, isFalse);
    },
  );

  test(
    'nonterminal refresh retains a cached trailing root and its branch',
    () async {
      final loader = _Loader()
        ..rootHandler = (_) async => _roots([
          node(2),
          node(4, children: [node(5, parent: 4)]),
        ], hasMore: true);
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      loader.rootHandler = (_) async =>
          _roots([node(3), node(2)], hasMore: true);
      await controller.refreshVisit();
      expect(controller.roots.map((node) => node.postNumber), [2, 4]);
      expect(controller.childrenFor(4).single.postNumber, 5);
      expect(controller.pendingRoots.single.postNumber, 3);
      loader.rootHandler = (_) async => _roots([node(2)]);
      await controller.refreshVisit();
      expect(controller.roots.single.postNumber, 2);
      expect(controller.postNumber(4), isNull);
      expect(controller.pendingRoots, isEmpty);
    },
  );

  test(
    'failed foreground reconciliation retains the cached graph for retry',
    () async {
      final loader = _Loader()..rootHandler = (_) async => _roots([node(2)]);
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      loader.rootHandler = (_) async => throw StateError('Offline');
      var applied = false;
      await controller.refreshVisit(beforeApply: () => applied = true);
      expect(controller.error, isStateError);
      expect(controller.roots.single.postNumber, 2);
      expect(controller.restoringPages, isFalse);
      expect(applied, isFalse);
      loader.rootHandler = (_) async => _roots([node(3), node(2)]);
      await controller.refreshVisit();
      expect(controller.error, isNull);
      expect(controller.pendingRoots.single.postNumber, 3);
    },
  );

  test('a newer foreground refresh supersedes an older staged graph', () async {
    final loader = _Loader()..rootHandler = (_) async => _roots([node(2)]);
    final controller = NestedRepliesController(loader: loader);
    addTearDown(controller.dispose);
    await controller.open();
    final older = Completer<NestedPageReceipt<NestedRootPage>?>();
    final newer = Completer<NestedPageReceipt<NestedRootPage>?>();
    loader.rootHandler = (_) => older.future;
    var olderApplied = false;
    final first = controller.refreshVisit(
      beforeApply: () => olderApplied = true,
    );
    loader.rootHandler = (_) => newer.future;
    final second = controller.refreshVisit();
    newer.complete(_roots([node(3), node(2)]));
    await second;
    older.complete(_roots([node(4), node(2)]));
    await first;
    expect(olderApplied, isFalse);
    expect(controller.roots.single.postNumber, 2);
    expect(controller.pendingRoots.single.postNumber, 3);
    expect(controller.postNumber(4), isNull);
    expect(controller.restoringPages, isFalse);
  });

  test(
    'a child page cannot reopen a post collapsed while it was loading',
    () async {
      final pending = Completer<NestedPageReceipt<NestedChildrenPage>?>();
      final loader = _Loader()..rootHandler = (_) async => _roots([node(2)]);
      loader.childHandler = (_) => pending.future;
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      final loading = controller.loadChildren(2, depth: 1);
      controller.setCollapsed(2, true);
      pending.complete(_children([node(3, parent: 2)], hasMore: false));
      await loading;
      expect(controller.isCollapsed(2), isTrue);
      expect(controller.childrenFor(2).single.postNumber, 3);
      expect(controller.visibleRows().map((row) => row.node.postNumber), [2]);
    },
  );

  test(
    'foreground revisit reconciles loaded root and child pages with one visit',
    () async {
      final loader = _Loader();
      loader.rootHandler = (request) async => _roots(
        [node(request.page + 2)],
        page: request.page,
        hasMore: true,
        effective: NestedRepliesSort.top,
      );
      loader.childHandler = (request) async => _children(
        [node(10 + request.page, parent: 2)],
        page: request.page,
        hasMore: true,
      );
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open(sort: NestedRepliesSort.hot);
      await controller.loadMoreRoots();
      await controller.loadMoreRoots();
      await controller.loadChildren(2, depth: 1);
      await controller.loadChildren(2, depth: 1);
      controller.setCollapsed(2, true);
      controller.updatePins([104]);
      final saved = controller.snapshot();
      expect(identical(saved, controller.snapshot()), isTrue);
      final restored = NestedRepliesController(loader: loader);
      addTearDown(restored.dispose);
      restored.restore(saved);
      await restored.refreshVisit();
      expect(loader.rootRequests.map((request) => request.page), [
        0,
        1,
        2,
        0,
        1,
        2,
      ]);
      expect(loader.rootRequests.map((request) => request.trackVisit), [
        true,
        false,
        false,
        true,
        false,
        false,
      ]);
      expect(restored.rootPage, 2);
      expect(restored.childrenState(2, depth: 1).page, 1);
      expect(restored.childrenFor(2).map((node) => node.postNumber), [10, 11]);
      expect(restored.roots.map((node) => node.postNumber), [2, 3, 4]);
      expect(restored.pinnedPostIds, isEmpty);
      expect(restored.requestedSort, NestedRepliesSort.hot);
      expect(restored.effectiveSort, NestedRepliesSort.top);
      expect(restored.isCollapsed(2), isTrue);
      expect(identical(saved, restored.snapshot()), isFalse);
      await restored.loadMoreRoots();
      expect(loader.rootRequests.last.page, 3);
    },
  );

  test('reload restores the loaded page depth and collapsed posts', () async {
    final loader = _Loader();
    loader.rootHandler = (request) async =>
        _roots([node(request.page + 2)], page: request.page, hasMore: true);
    loader.childHandler = (request) async => _children(
      [node(10 + request.page, parent: 2)],
      page: request.page,
      hasMore: true,
    );
    final controller = NestedRepliesController(loader: loader);
    addTearDown(controller.dispose);
    await controller.open();
    await controller.loadMoreRoots();
    await controller.loadChildren(2, depth: 1);
    await controller.loadChildren(2, depth: 1);
    controller.setCollapsed(2, true);
    await controller.reload();
    expect(
      loader.rootRequests.map((request) => (request.page, request.trackVisit)),
      [(0, true), (1, false), (0, false), (1, false)],
    );
    expect(controller.rootPage, 1);
    expect(controller.childrenState(2, depth: 1).page, 1);
    expect(controller.childrenFor(2).map((node) => node.postNumber), [10, 11]);
    expect(controller.isCollapsed(2), isTrue);
    expect(controller.restoringPages, isFalse);
  });

  test('superseded reload cannot replay old pages into a new sort', () async {
    final loader = _Loader()
      ..rootHandler = (request) async =>
          _roots([node(request.page + 2)], page: request.page, hasMore: true);
    final controller = NestedRepliesController(loader: loader);
    addTearDown(controller.dispose);
    await controller.open();
    await controller.loadMoreRoots();
    final pending = Completer<NestedPageReceipt<NestedRootPage>?>();
    loader.rootHandler = (request) => request.sort == NestedRepliesSort.top
        ? pending.future
        : Future.value(_roots([node(8)], hasMore: true));
    final reloading = controller.reload();
    await controller.changeSort(NestedRepliesSort.newest);
    pending.complete(_roots([node(2)], hasMore: true));
    await reloading;
    expect(controller.requestedSort, NestedRepliesSort.newest);
    expect(controller.rootPage, 0);
    expect(controller.roots.single.postNumber, 8);
    expect(loader.rootRequests.map((request) => (request.sort, request.page)), [
      (NestedRepliesSort.top, 0),
      (NestedRepliesSort.top, 1),
      (NestedRepliesSort.top, 0),
      (NestedRepliesSort.newest, 0),
    ]);
  });

  test(
    'effective sort controls later pages and visits are foreground entry only',
    () async {
      final loader = _Loader();
      loader.rootHandler = (request) async => _roots(
        [node(request.page == 0 ? 2 : 3)],
        page: request.page,
        hasMore: request.page == 0,
        effective: NestedRepliesSort.top,
      );
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open(sort: NestedRepliesSort.hot);
      await controller.loadMoreRoots();
      expect(controller.requestedSort, NestedRepliesSort.hot);
      expect(loader.rootRequests.map((value) => value.sort), [
        NestedRepliesSort.hot,
        NestedRepliesSort.top,
      ]);
      expect(loader.rootRequests.map((value) => value.trackVisit), [
        true,
        false,
      ]);
      expect(controller.roots.map((value) => value.postNumber), [2, 3]);
      expect(controller.hasMoreRoots, isFalse);
      await controller.open(foreground: false);
      expect(loader.rootRequests.last.trackVisit, isFalse);
    },
  );

  test(
    'first explicit child fetch is page zero and retains expanded preloads',
    () async {
      final loader = _Loader();
      loader.rootHandler = (_) async => _roots([
        node(
          2,
          children: [
            node(4, parent: 2, children: [node(5, parent: 4)]),
          ],
        ),
      ]);
      loader.childHandler = (request) async => _children(
        request.page == 0
            ? [node(4, parent: 2), node(6, parent: 2)]
            : [node(6, parent: 2), node(7, parent: 2)],
        page: request.page,
        hasMore: request.page == 0,
      );
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      controller.setCollapsed(4, false);
      await controller.loadChildren(2, depth: 1);
      expect(loader.childRequests.single.page, 0);
      expect(controller.childrenFor(2).map((value) => value.postNumber), [
        4,
        6,
      ]);
      expect(controller.childrenFor(4).single.postNumber, 5);
      expect(controller.isExpanded(4, depth: 1), isTrue);
      await controller.loadChildren(2, depth: 1);
      expect(loader.childRequests.map((value) => value.page), [0, 1]);
      expect(controller.childrenFor(2).map((value) => value.postNumber), [
        4,
        6,
        7,
      ]);
      expect(controller.childrenState(2, depth: 1).hasMore, isFalse);
    },
  );

  test('flattened display edges retain original reply parents', () async {
    final loader = _Loader()..rootHandler = (_) async => _roots([node(2)]);
    loader.childHandler = (_) async =>
        _children([node(8, parent: 6)], hasMore: false);
    final controller = NestedRepliesController(
      loader: loader,
      settings: const NestedRepliesSettings(maxDepth: 1),
    );
    addTearDown(controller.dispose);
    await controller.open();
    await controller.loadChildren(2, depth: 1);
    final rows = controller.visibleRows();
    expect(rows.map((value) => value.node.postNumber), [2, 8]);
    expect(rows.last.displayParentPostNumber, 2);
    expect(rows.last.node.data.replyToPostNumber, 6);
  });

  test(
    'sort replacement discards old children without disturbing new loading',
    () async {
      final roots = Completer<NestedPageReceipt<NestedRootPage>?>();
      final children = Completer<NestedPageReceipt<NestedChildrenPage>?>();
      final loader = _Loader()..rootHandler = (_) async => _roots([node(2)]);
      loader.childHandler = (_) => children.future;
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      final pendingChildren = controller.loadChildren(2, depth: 1);
      loader.rootHandler = (_) => roots.future;
      final pendingSort = controller.changeSort(NestedRepliesSort.newest);
      children.complete(_children([node(9, parent: 2)]));
      await pendingChildren;
      expect(controller.loading, isTrue);
      expect(controller.postNumber(9), isNull);
      roots.complete(_roots([node(3)], effective: NestedRepliesSort.newest));
      await pendingSort;
      expect(controller.loading, isFalse);
      expect(controller.roots.single.postNumber, 3);
    },
  );

  test(
    'retired loader cannot publish results or clean up successor state',
    () async {
      final result = Completer<NestedPageReceipt<NestedRootPage>?>();
      final loader = _Loader()..rootHandler = (_) => result.future;
      final controller = NestedRepliesController(loader: loader);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final opening = controller.open();
      expect(notifications, 1);
      loader.current = false;
      result.complete(_roots([node(2)]));
      await opening;
      expect(controller.roots, isEmpty);
      expect(notifications, 1);
      controller.dispose();
    },
  );

  test(
    'independent parent requests do not serialize and failed pages retry unchanged',
    () async {
      final left = Completer<NestedPageReceipt<NestedChildrenPage>?>();
      final right = Completer<NestedPageReceipt<NestedChildrenPage>?>();
      final loader = _Loader();
      loader.rootHandler = (_) async => _roots([node(2), node(3)]);
      loader.childHandler = (request) =>
          request.parentPostNumber == 2 ? left.future : right.future;
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      final a = controller.loadChildren(2, depth: 1);
      final b = controller.loadChildren(3, depth: 1);
      expect(loader.childRequests.length, 2);
      left.completeError(StateError('Offline'));
      right.complete(_children([node(8, parent: 3)], hasMore: false));
      await Future.wait([a, b]);
      expect(controller.childrenState(2, depth: 1).error, isStateError);
      expect(controller.childrenFor(3).single.postNumber, 8);
      loader.childHandler = (request) async =>
          _children([node(6, parent: 2)], hasMore: false);
      await controller.loadChildren(2, depth: 1);
      expect(loader.childRequests.last.page, 0);
      expect(controller.childrenState(2, depth: 1).error, isNull);
    },
  );

  test('rejected canonical posts cannot create a visible graph node', () async {
    final loader = _Loader()
      ..rootHandler = (_) async {
        final page = _rootPage([
          node(2, children: [node(3, parent: 2)]),
        ]);
        return NestedPageReceipt(value: page, acceptedPostIds: [102]);
      };
    final controller = NestedRepliesController(loader: loader);
    addTearDown(controller.dispose);
    await controller.open();
    expect(controller.roots.single.postNumber, 2);
    expect(controller.childrenFor(2), isEmpty);
    expect(controller.postNumber(3), isNull);
  });

  test(
    'context reconstructs ancestors while collapse intent keeps target reachable',
    () async {
      final loader = _Loader();
      loader.contextHandler = (_) async {
        final target = node(
          8,
          parent: 4,
          children: [
            node(9, parent: 8, children: [node(10, parent: 9)]),
          ],
        );
        final ancestors = [node(2), node(4, parent: 2)];
        final all = [..._all(target), ...ancestors];
        return NestedPageReceipt(
          value: NestedContextPage(
            topicMetadata: const {'id': 7},
            op: null,
            target: target,
            ancestors: ancestors,
            siblings: const {},
            posts: all.map(_payload),
            ancestorsTruncated: true,
            effectiveSort: NestedRepliesSort.newest,
          ),
          acceptedPostIds: all.map((value) => value.postId),
        );
      };
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open(postNumber: 8, collapse: true);
      expect(controller.contextMode, isTrue);
      expect(controller.ancestorsTruncated, isTrue);
      expect(controller.visibleRows().map((row) => row.node.postNumber), [
        2,
        4,
        8,
        9,
      ]);
      expect(controller.target!.postNumber, 8);
      expect(loader.contextRequests.single.postNumber, 8);
    },
  );

  test(
    'other roots wait for an explicit action and duplicate events insert once',
    () async {
      final loader = _Loader()..rootHandler = (_) async => _roots([node(2)]);
      final controller = NestedRepliesController(loader: loader);
      addTearDown(controller.dispose);
      await controller.open();
      controller.queueRoot(node(3), own: false);
      controller.queueRoot(node(3), own: false);
      expect(controller.roots.map((value) => value.postNumber), [2]);
      expect(controller.pendingRoots.map((value) => value.postNumber), [3]);
      controller.queueRoot(node(4), own: true);
      expect(controller.roots.map((value) => value.postNumber), [4, 2]);
      controller.showPendingRoots();
      expect(controller.roots.map((value) => value.postNumber), [3, 4, 2]);
      expect(controller.pendingRoots, isEmpty);
    },
  );
}

typedef _RootRequest = ({NestedRepliesSort sort, int page, bool trackVisit});
typedef _ChildRequest = ({
  NestedRepliesSort sort,
  int parentPostNumber,
  int depth,
  int page,
});
typedef _ContextRequest = ({
  NestedRepliesSort sort,
  int postNumber,
  int? contextDepth,
  bool trackVisit,
});

final class _Loader implements NestedRepliesLoader {
  bool current = true;
  final rootRequests = <_RootRequest>[];
  final childRequests = <_ChildRequest>[];
  final contextRequests = <_ContextRequest>[];
  late Future<NestedPageReceipt<NestedRootPage>?> Function(_RootRequest)
  rootHandler;
  late Future<NestedPageReceipt<NestedChildrenPage>?> Function(_ChildRequest)
  childHandler;
  late Future<NestedPageReceipt<NestedContextPage>?> Function(_ContextRequest)
  contextHandler;

  @override
  bool get isCurrent => current;
  @override
  Future<NestedPageReceipt<NestedRootPage>?> roots({
    required NestedRepliesSort sort,
    required int page,
    required bool trackVisit,
  }) {
    final request = (sort: sort, page: page, trackVisit: trackVisit);
    rootRequests.add(request);
    return rootHandler(request);
  }

  @override
  Future<NestedPageReceipt<NestedChildrenPage>?> children({
    required NestedRepliesSort sort,
    required int parentPostNumber,
    required int depth,
    required int page,
  }) {
    final request = (
      sort: sort,
      parentPostNumber: parentPostNumber,
      depth: depth,
      page: page,
    );
    childRequests.add(request);
    return childHandler(request);
  }

  @override
  Future<NestedPageReceipt<NestedContextPage>?> context({
    required NestedRepliesSort sort,
    required int postNumber,
    required int? contextDepth,
    required bool trackVisit,
  }) {
    final request = (
      sort: sort,
      postNumber: postNumber,
      contextDepth: contextDepth,
      trackVisit: trackVisit,
    );
    contextRequests.add(request);
    return contextHandler(request);
  }
}

NestedReplyNode node(
  int number, {
  int? parent,
  List<NestedReplyNode> children = const [],
}) => NestedReplyNode(
  postId: number + 100,
  postNumber: number,
  data: NestedPostData(
    replyToPostNumber: parent,
    directReplyCount: children.length,
    totalDescendantCount: children.length,
  ),
  children: children,
);
Iterable<NestedReplyNode> _all(NestedReplyNode value) sync* {
  yield value;
  for (final child in value.children) {
    yield* _all(child);
  }
}

NestedPostPayload _payload(NestedReplyNode node) => NestedPostPayload(
  post: Post(
    id: node.postId,
    postNumber: node.postNumber,
    username: 'alice',
    cooked: '<p>Post</p>',
  ),
  data: node.data,
);
NestedRootPage _rootPage(
  List<NestedReplyNode> roots, {
  int page = 0,
  bool hasMore = false,
  NestedRepliesSort effective = NestedRepliesSort.top,
}) => NestedRootPage(
  roots: roots,
  posts: roots.expand(_all).map(_payload),
  page: page,
  hasMore: hasMore,
  effectiveSort: effective,
);
NestedPageReceipt<NestedRootPage> _roots(
  List<NestedReplyNode> roots, {
  int page = 0,
  bool hasMore = false,
  NestedRepliesSort effective = NestedRepliesSort.top,
}) {
  final value = _rootPage(
    roots,
    page: page,
    hasMore: hasMore,
    effective: effective,
  );
  return NestedPageReceipt(
    value: value,
    acceptedPostIds: value.posts.map((value) => value.post.id),
  );
}

NestedPageReceipt<NestedChildrenPage> _children(
  List<NestedReplyNode> nodes, {
  int page = 0,
  bool hasMore = true,
}) {
  final posts = nodes.expand(_all).map(_payload).toList();
  return NestedPageReceipt(
    value: NestedChildrenPage(
      children: nodes,
      posts: posts,
      page: page,
      hasMore: hasMore,
    ),
    acceptedPostIds: posts.map((value) => value.post.id),
  );
}
