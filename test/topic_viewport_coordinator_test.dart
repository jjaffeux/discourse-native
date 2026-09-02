// Kept free of testWidgets so the coordinator's pure-Dart construction stays
// pinned without a scheduler binding.
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TopicViewportCoordinator', () {
    test(
      'topic switches replace state and retire the previous controllers',
      () {
        final frames = _FrameQueue();
        final geometry = _Geometry();
        final disposed = <TopicViewportControllers>[];
        final subject = _coordinator(
          frames: frames,
          geometry: geometry,
          controllersDisposer: (controllers) {
            disposed.add(controllers);
            controllers.scroll.dispose();
            controllers.list.dispose();
          },
        );
        _disposeAfter(subject, frames);
        final first = _Owner(_snapshot(topicId: 1, postIds: const [10, 11]));
        final second = _Owner(_snapshot(topicId: 2, postIds: const [20, 21]));

        subject.bind(first.binding);
        final firstScroll = subject.scrollController;
        subject
          ..restoreInitialPost(first.snapshot)
          ..updateLaidOutSnapshot(first.snapshot)
          ..recordObservation(
            snapshot: first.snapshot,
            saveAnchor: false,
            visible: const (postId: 11, postNumber: 2, caughtUp: true),
          )
          ..updateFloatingDay(DateTime(2026, 8, 30), -4);

        expect(subject.progressPosition, 2);
        expect(subject.floatingDay, DateTime(2026, 8, 30));

        subject.bind(second.binding);

        expect(subject.identity?.topicId, 2);
        expect(subject.scrollController, isNot(same(firstScroll)));
        expect(subject.progressPosition, isNull);
        expect(subject.floatingDay, isNull);
        expect(disposed, isEmpty);

        frames.flushFrame();

        expect(disposed, hasLength(1));
      },
    );

    test(
      'dispose rejects queued work and retires its controller generation',
      () {
        final frames = _FrameQueue();
        final geometry = _Geometry();
        final disposed = <TopicViewportControllers>[];
        final subject = _coordinator(
          frames: frames,
          geometry: geometry,
          controllersDisposer: (controllers) {
            disposed.add(controllers);
            controllers.scroll.dispose();
            controllers.list.dispose();
          },
        );
        final owner = _Owner(
          _snapshot(topicId: 1, postIds: const [10], hasMore: true),
        );
        subject
          ..bind(owner.binding)
          ..scheduleLoadMore(owner.snapshot)
          ..dispose();

        frames.flushAll();

        expect(owner.loadMoreCount, 0);
        expect(owner.flushCount, 1);
        expect(disposed, hasLength(1));
      },
    );

    test(
      'pause credits the visible post and resume restarts pending dwell',
      () async {
        final frames = _FrameQueue();
        final geometry = _Geometry();
        final clock = _ManualClock();
        final subject = _coordinator(
          frames: frames,
          geometry: geometry,
          clock: clock,
        );
        _disposeAfter(subject, frames);
        final owner = _Owner(_snapshot(topicId: 1, postIds: const [10, 11]));
        subject
          ..bind(owner.binding)
          ..restoreInitialPost(owner.snapshot)
          ..recordObservation(
            snapshot: owner.snapshot,
            saveAnchor: false,
            visible: const (postId: 10, postNumber: 1, caughtUp: false),
            readable: const (postId: 10, postNumber: 1, caughtUp: false),
          );
        clock.elapse(const Duration(milliseconds: 200));

        subject.handleAppLifecycleState(AppLifecycleState.paused);
        await _drainMicrotasks();

        expect(owner.reads, const [(postNumber: 1, caughtUp: false)]);

        subject.recordObservation(
          snapshot: owner.snapshot,
          saveAnchor: false,
          visible: const (postId: 11, postNumber: 2, caughtUp: true),
          readable: const (postId: 11, postNumber: 2, caughtUp: true),
        );
        clock.elapse(const Duration(seconds: 1));
        expect(owner.reads, hasLength(1));

        subject.handleAppLifecycleState(AppLifecycleState.resumed);
        clock.elapse(const Duration(milliseconds: 499));
        expect(owner.reads, hasLength(1));
        clock.elapse(const Duration(milliseconds: 1));
        await _drainMicrotasks();

        expect(owner.reads, const [
          (postNumber: 1, caughtUp: false),
          (postNumber: 2, caughtUp: true),
        ]);
      },
    );

    test('a saved position past the stream restores at the last post', () {
      final frames = _FrameQueue();
      final geometry = _Geometry();
      final subject = _coordinator(frames: frames, geometry: geometry);
      _disposeAfter(subject, frames);
      final owner = _Owner(_snapshot(topicId: 1, postIds: const [10, 11]))
        ..savedPostNumber = 99;

      subject
        ..bind(owner.binding)
        ..restoreInitialPost(owner.snapshot);
      frames.flushFrame();
      frames.flushFrame();
      subject.recordObservation(
        snapshot: owner.snapshot,
        saveAnchor: false,
        visible: const (postId: 11, postNumber: 2, caughtUp: true),
      );

      expect(
        subject.progressPosition,
        2,
        reason: 'the reader is restored, so what is on screen counts',
      );
    });

    test(
      'a saved position past a window that can still grow keeps waiting',
      () {
        final frames = _FrameQueue();
        final geometry = _Geometry();
        final subject = _coordinator(frames: frames, geometry: geometry);
        _disposeAfter(subject, frames);
        final owner = _Owner(
          _snapshot(topicId: 1, postIds: const [10, 11], hasMore: true),
        )..savedPostNumber = 99;

        subject
          ..bind(owner.binding)
          ..restoreInitialPost(owner.snapshot);
        frames.flushFrame();
        subject.recordObservation(
          snapshot: owner.snapshot,
          saveAnchor: false,
          visible: const (postId: 11, postNumber: 2, caughtUp: true),
        );

        expect(subject.progressPosition, isNull);
      },
    );

    test('queued paging is deduplicated, stale-checked, and retryable', () {
      final frames = _FrameQueue();
      final geometry = _Geometry();
      final diagnostics = <String>[];
      final subject = _coordinator(
        frames: frames,
        geometry: geometry,
        diagnostics: diagnostics,
      );
      _disposeAfter(subject, frames);
      final first = _snapshot(topicId: 1, postIds: const [10], hasMore: true);
      final owner = _Owner(first);
      subject.bind(owner.binding);

      subject
        ..scheduleLoadMore(first)
        ..scheduleLoadMore(first);
      frames.flushFrame();

      expect(owner.loadMoreCount, 1);

      subject.scheduleLoadMore(first);
      frames.flushFrame();
      expect(owner.loadMoreCount, 1);

      subject
        ..allowLoadMoreRetry(first)
        ..scheduleLoadMore(first);
      owner.snapshot = _snapshot(
        topicId: 1,
        postIds: const [10, 11],
        hasMore: true,
      );
      frames.flushFrame();
      expect(owner.loadMoreCount, 1);

      subject.scheduleLoadMore(owner.snapshot);
      frames.flushFrame();
      expect(owner.loadMoreCount, 2);
      expect(
        diagnostics,
        containsAllInOrder(const [
          'paging.newer.scheduled',
          'paging.newer.dispatched',
          'paging.newer.retryArmed',
          'paging.newer.scheduled',
          'paging.newer.cancelled',
          'paging.newer.scheduled',
          'paging.newer.dispatched',
        ]),
      );
    });

    test('topic switches reject paging queued by the previous generation', () {
      final frames = _FrameQueue();
      final geometry = _Geometry();
      final subject = _coordinator(frames: frames, geometry: geometry);
      _disposeAfter(subject, frames);
      final first = _Owner(
        _snapshot(topicId: 1, postIds: const [10], hasMore: true),
      );
      final second = _Owner(
        _snapshot(topicId: 2, postIds: const [20], hasMore: true),
      );
      subject
        ..bind(first.binding)
        ..scheduleLoadMore(first.snapshot)
        ..bind(second.binding);

      frames.flushAll();

      expect(first.loadMoreCount, 0);
      expect(second.loadMoreCount, 0);
    });

    test('anchor correction preserves the requested viewport offset', () {
      final frames = _FrameQueue();
      final geometry = _Geometry()
        ..offsets[11] = 40
        ..position = (pixels: 100, minScrollExtent: 0, maxScrollExtent: 500);
      final diagnostics = <String>[];
      final subject = _coordinator(
        frames: frames,
        geometry: geometry,
        diagnostics: diagnostics,
      );
      _disposeAfter(subject, frames);
      final owner = _Owner(_snapshot(topicId: 1, postIds: const [10, 11]));
      subject
        ..bind(owner.binding)
        ..updateLaidOutSnapshot(owner.snapshot)
        ..holdViewportAnchor(11, 0, token: Object())
        ..holdViewportAnchor(11, 10, token: Object());

      frames.flushFrame();

      expect(geometry.pixelJumps, [130]);

      geometry.offsets.remove(11);
      subject.holdViewportAnchor(11, 10, token: Object());
      frames.flushFrame();

      expect(geometry.itemJumps, const [(itemIndex: 1, viewportOffset: 10)]);
      expect(
        diagnostics,
        containsAll(const [
          'viewport.anchor.held',
          'viewport.anchor.correctionScheduled',
          'viewport.anchor.correcting',
          'viewport.anchor.jumpToItem',
        ]),
      );
    });
  });
}

TopicViewportCoordinator _coordinator({
  required _FrameQueue frames,
  required _Geometry geometry,
  _ManualClock? clock,
  TopicViewportControllersDisposer? controllersDisposer,
  List<String>? diagnostics,
}) => TopicViewportCoordinator(
  postFrame: frames.schedule,
  geometry: geometry,
  inspectViewport: (_, {required saveAnchor}) {},
  timerFactory: clock?.startTimer,
  clock: clock?.now,
  controllersDisposer: controllersDisposer,
  diagnosticsEnabled: () => diagnostics != null,
  recordDiagnostic: (name, data) => diagnostics?.add(name),
  layoutDiagnostics: () => const {'attached': false},
);

TopicViewportSnapshot _snapshot({
  required int topicId,
  required List<int> postIds,
  bool hasMore = false,
  bool hasEarlier = false,
}) => TopicViewportSnapshot(
  topicId: topicId,
  topic: TopicDetail(
    id: topicId,
    title: 'Topic $topicId',
    stream: postIds,
    postsCount: postIds.length,
  ),
  siteUrl: 'https://meta.example',
  postIds: postIds,
  streamIds: postIds,
  loading: false,
  loadingMore: false,
  loadingEarlier: false,
  hasMore: hasMore,
  hasEarlier: hasEarlier,
  initialPostIndex: null,
  recommendations: null,
  summary: false,
  summaryLoading: false,
  readTimeWordCount: 500,
  showTimeGapDays: 14,
  navigationRevision: topicId,
);

final class _Owner {
  _Owner(this.snapshot);

  TopicViewportSnapshot snapshot;
  bool current = true;
  bool forumActive = true;
  int? savedPostNumber;
  int loadMoreCount = 0;
  int loadEarlierCount = 0;
  int flushCount = 0;
  final List<({int postNumber, bool caughtUp})> reads = [];
  final List<({int postNumber, double viewportOffset})> anchors = [];

  late final TopicViewportBinding binding = TopicViewportBinding(
    owner: this,
    identity: (
      siteUrl: snapshot.siteUrl!,
      topicId: snapshot.topicId!,
      navigationRevision: snapshot.navigationRevision,
    ),
    tabId: 'tab',
    isCurrent: () => current,
    currentSnapshot: () => snapshot,
    forumActive: () => forumActive,
    loadMore: () async => loadMoreCount++,
    loadEarlier: () async => loadEarlierCount++,
    markRead:
        ({
          required siteUrl,
          required topicId,
          required postNumber,
          required caughtUp,
        }) async => reads.add((postNumber: postNumber, caughtUp: caughtUp)),
    saveAnchor: (topicId, postNumber, viewportOffset) =>
        anchors.add((postNumber: postNumber, viewportOffset: viewportOffset)),
    flushAnchorPersist: () => flushCount++,
    savedPostNumber: () => savedPostNumber,
    savedPostOffset: () => 0,
    postNumberFor: (postId) => null,
  );
}

final class _Geometry implements TopicViewportGeometry {
  final Map<int, double> offsets = {};
  TopicViewportAnchor? capturedAnchor;
  TopicViewportScrollPosition position = (
    pixels: 0,
    minScrollExtent: 0,
    maxScrollExtent: 0,
  );
  final List<double> pixelJumps = [];
  final List<({int itemIndex, double viewportOffset})> itemJumps = [];

  @override
  bool get canCorrectAnchor => true;

  @override
  TopicViewportAnchor? captureAnchor(
    List<int> postIds, {
    required bool hasHeader,
  }) => capturedAnchor;

  @override
  void jumpToPixels(double pixels) {
    pixelJumps.add(pixels);
    position = (
      pixels: pixels,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
  }

  @override
  void jumpToPost(int itemIndex, {required double viewportOffset}) {
    itemJumps.add((itemIndex: itemIndex, viewportOffset: viewportOffset));
  }

  @override
  double? postViewportOffset(int postId) => offsets[postId];

  @override
  TopicViewportScrollPosition get scrollPosition => position;
}

final class _FrameQueue {
  final List<VoidCallback> _callbacks = [];

  void schedule(VoidCallback callback) => _callbacks.add(callback);

  void flushFrame() {
    final current = List<VoidCallback>.of(_callbacks);
    _callbacks.removeRange(0, current.length);
    for (final callback in current) {
      callback();
    }
  }

  void flushAll() {
    while (_callbacks.isNotEmpty) {
      flushFrame();
    }
  }
}

final class _ManualClock {
  DateTime _now = DateTime.utc(2026, 8, 31, 12);
  final List<_ManualTimer> _timers = [];

  DateTime now() => _now;

  TopicViewportTimer startTimer(Duration duration, VoidCallback callback) {
    final timer = _ManualTimer(_now.add(duration), callback);
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    _now = _now.add(duration);
    final due = [
      for (final timer in _timers)
        if (!timer.cancelled && !timer.deadline.isAfter(_now)) timer,
    ];
    for (final timer in due) {
      timer
        ..cancelled = true
        ..callback();
    }
  }
}

final class _ManualTimer implements TopicViewportTimer {
  _ManualTimer(this.deadline, this.callback);

  final DateTime deadline;
  final VoidCallback callback;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;
}

Future<void> _drainMicrotasks() async {
  await Future<void>.value();
  await Future<void>.value();
}

void _disposeAfter(TopicViewportCoordinator subject, _FrameQueue frames) {
  addTearDown(() {
    subject.dispose();
    frames.flushAll();
  });
}
