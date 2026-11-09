// Drives the coordinator's default timer under fake_async, so a reader's dwell
// runs through the same construction production uses.
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a clock set back during a dwell cannot stretch it', () {
    fakeAsync((async) {
      var now = DateTime.utc(2026, 8, 31, 12);
      final reads = <({int postNumber, bool caughtUp})>[];
      final snapshot = _snapshot();
      final subject = TopicViewportCoordinator(
        postFrame: (_) {},
        geometry: _Geometry(),
        inspectViewport: (_, {required saveAnchor}) {},
        clock: () => now,
      );
      subject
        ..bind(_binding(snapshot, reads))
        ..restoreInitialPost(snapshot)
        ..recordObservation(
          snapshot: snapshot,
          saveAnchor: false,
          visible: const (postId: 10, postNumber: 1, caughtUp: false),
          readable: const (postId: 10, postNumber: 1, caughtUp: false),
        );

      async.elapse(const Duration(milliseconds: 200));
      now = now.subtract(const Duration(hours: 1));
      subject
        ..setTickerEnabled(false)
        ..setTickerEnabled(true);
      async
        ..elapse(const Duration(milliseconds: 500))
        ..flushMicrotasks();

      // ignore: avoid_print
      print(
        'PERF_PROOF read-dwell-owner '
        'topic_credited_after_clock_back=${reads.length}',
      );
      expect(reads, const [(postNumber: 1, caughtUp: false)]);

      subject.dispose();
      async.flushMicrotasks();
    });
  });
}

TopicViewportBinding _binding(
  TopicViewportSnapshot snapshot,
  List<({int postNumber, bool caughtUp})> reads,
) => TopicViewportBinding(
  owner: reads,
  identity: (
    siteUrl: snapshot.siteUrl!,
    topicId: snapshot.topicId!,
    navigationRevision: snapshot.navigationRevision,
  ),
  tabId: 'tab',
  isCurrent: () => true,
  currentSnapshot: () => snapshot,
  forumActive: () => true,
  loadMore: () async {},
  loadEarlier: () async {},
  markRead:
      ({
        required siteUrl,
        required topicId,
        required postNumber,
        required caughtUp,
        required readPostNumbers,
      }) async => reads.add((postNumber: postNumber, caughtUp: caughtUp)),
  saveAnchor: (topicId, postNumber, viewportOffset) {},
  flushAnchorPersist: () {},
  savedPostNumber: () => null,
  savedPostOffset: () => 0,
  postNumberFor: (postId) => null,
);

TopicViewportSnapshot _snapshot() => const TopicViewportSnapshot(
  topicId: 1,
  topic: TopicDetail(id: 1, title: 'Topic 1', stream: [10], postsCount: 1),
  siteUrl: 'https://meta.example',
  postIds: [10],
  streamIds: [10],
  loading: false,
  loadingMore: false,
  loadingEarlier: false,
  hasMore: false,
  hasEarlier: false,
  initialPostIndex: null,
  recommendations: null,
  summary: false,
  summaryLoading: false,
  readTimeWordCount: 500,
  showTimeGapDays: 14,
  navigationRevision: 1,
);

final class _Geometry implements TopicViewportGeometry {
  @override
  bool get canCorrectAnchor => true;

  @override
  double get viewportTopInset => 0;

  @override
  TopicViewportScrollPosition get scrollPosition =>
      (pixels: 0, minScrollExtent: 0, maxScrollExtent: 0);

  @override
  TopicViewportAnchor? captureAnchor(
    List<int> postIds, {
    required bool hasHeader,
  }) => null;

  @override
  double constrainPostViewportOffset(int postId, double viewportOffset) =>
      viewportOffset;

  @override
  double? postViewportOffset(int postId) => null;

  @override
  void jumpToPixels(double pixels) {}

  @override
  void jumpToPost(int itemIndex, {required double viewportOffset}) {}
}
