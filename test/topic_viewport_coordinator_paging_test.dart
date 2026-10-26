// Earlier paging reads the laid-out scroll position, so these cases attach the
// coordinator's ScrollController to a real scroll view. They live apart from
// topic_viewport_coordinator_test.dart, which must never initialise a binding.
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'queued earlier paging is dropped once its binding stops being current',
    (tester) async {
      final rig = await _Rig.attach(tester);

      rig.subject.scheduleLoadEarlier(rig.snapshot);
      rig.current = false;
      rig.flushFrame();

      expect(rig.loadEarlierCount, 0);

      rig.current = true;
      rig.subject.scheduleLoadEarlier(rig.snapshot);
      rig.flushFrame();
      expect(rig.loadEarlierCount, 1);
      await rig.detach(tester);
    },
  );
}

final class _Rig {
  _Rig._();

  static Future<_Rig> attach(WidgetTester tester) async {
    final rig = _Rig._();
    rig.subject.bind(rig.binding);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          controller: rig.subject.scrollController,
          children: const [SizedBox(height: 100)],
        ),
      ),
    );
    return rig;
  }

  final List<VoidCallback> _frames = [];
  late final TopicViewportCoordinator subject = TopicViewportCoordinator(
    postFrame: _frames.add,
    geometry: _Geometry(),
    inspectViewport: (_, {required saveAnchor}) {},
  );
  final TopicViewportSnapshot snapshot = const TopicViewportSnapshot(
    topicId: 1,
    topic: TopicDetail(id: 1, title: 'Topic 1', stream: [9, 10], postsCount: 2),
    siteUrl: 'https://meta.example',
    postIds: [10],
    streamIds: [9, 10],
    loading: false,
    loadingMore: false,
    loadingEarlier: false,
    hasMore: false,
    hasEarlier: true,
    initialPostIndex: null,
    recommendations: null,
    summary: false,
    summaryLoading: false,
    readTimeWordCount: 500,
    showTimeGapDays: 14,
    navigationRevision: 1,
  );
  bool current = true;
  int loadEarlierCount = 0;

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
    forumActive: () => true,
    loadMore: () async {},
    loadEarlier: () async => loadEarlierCount++,
    markRead:
        ({
          required siteUrl,
          required topicId,
          required postNumber,
          required caughtUp,
          required readPostNumbers,
        }) async {},
    saveAnchor: (_, _, _) {},
    flushAnchorPersist: () {},
    savedPostNumber: () => null,
    savedPostOffset: () => 0,
    postNumberFor: (_) => null,
  );

  void flushFrame() {
    final pending = List<VoidCallback>.of(_frames);
    _frames.clear();
    for (final callback in pending) {
      callback();
    }
  }

  Future<void> detach(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    subject.dispose();
  }
}

final class _Geometry implements TopicViewportGeometry {
  @override
  double get viewportTopInset => 0;

  @override
  bool get canCorrectAnchor => true;

  @override
  TopicViewportAnchor? captureAnchor(
    List<int> postIds, {
    required bool hasHeader,
  }) => null;

  @override
  double? postViewportOffset(int postId) => null;

  @override
  TopicViewportScrollPosition get scrollPosition =>
      (pixels: 0, minScrollExtent: 0, maxScrollExtent: 0);

  @override
  void jumpToPost(int itemIndex, {required double viewportOffset}) {}

  @override
  void jumpToPixels(double pixels) {}
}
