import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_post_sliver.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  test('retained heights preserve exact identity and every layout key', () {
    final list = _MeasuredList();
    final geometry = _geometry(list);
    const post = Post(
      id: 41,
      postNumber: 1,
      username: 'reader',
      cooked: '<p>A</p>',
    );
    const topic = TopicDetail(id: 1, title: 'Topic', stream: [41]);
    final snapshot = _snapshot(topic);
    geometry.applyWindowChange(_windowChange(const [], const [41]));
    expect(
      geometry.rememberPostExtent(41, post: post, snapshot: snapshot),
      isTrue,
    );
    expect(geometry.minimumHeightFor(41, post: post, snapshot: snapshot), 800);
    list.height = 100;
    expect(
      geometry.rememberPostExtent(41, post: post, snapshot: snapshot),
      isFalse,
    );
    expect(geometry.minimumHeightFor(41, post: post, snapshot: snapshot), 800);

    expect(
      geometry.minimumHeightFor(41, post: null, snapshot: snapshot),
      isNull,
    );
    expect(
      geometry.minimumHeightFor(41, post: post.copyWith(), snapshot: snapshot),
      isNull,
    );
    for (final changed in [
      _snapshot(topic.copyWith()),
      _snapshot(null),
      _snapshot(topic, summary: true),
      _snapshot(topic, summaryLoading: true),
      _snapshot(topic, readTimeWordCount: 10),
    ]) {
      expect(
        geometry.minimumHeightFor(41, post: post, snapshot: changed),
        isNull,
      );
    }
    geometry.postWidth += .49;
    expect(geometry.minimumHeightFor(41, post: post, snapshot: snapshot), 800);
    geometry.postWidth += .01;
    expect(
      geometry.minimumHeightFor(41, post: post, snapshot: snapshot),
      isNull,
    );
  });

  test(
    'heights survive a window round trip and refresh on changed records',
    () {
      final list = _MeasuredList();
      final geometry = _geometry(list);
      const post = Post(
        id: 41,
        postNumber: 1,
        username: 'reader',
        cooked: '<p>A</p>',
      );
      const topic = TopicDetail(id: 1, title: 'Topic', stream: [41, 42]);
      final snapshot = _snapshot(topic);
      geometry.applyWindowChange(_windowChange(const [], const [41]));
      expect(
        geometry.rememberPostExtent(41, post: post, snapshot: snapshot),
        isTrue,
      );
      geometry.applyWindowChange(_windowChange(const [41], const [42]));
      geometry.applyWindowChange(_windowChange(const [42], const [41]));
      expect(
        geometry.minimumHeightFor(41, post: post, snapshot: snapshot),
        800,
      );
      final edited = post.copyWith(cooked: '<p>Short edit</p>');
      list.height = 100;
      expect(
        geometry.rememberPostExtent(41, post: edited, snapshot: snapshot),
        isTrue,
      );
      expect(
        geometry.minimumHeightFor(41, post: edited, snapshot: snapshot),
        100,
      );
      final changedTopic = _snapshot(topic.copyWith(title: 'Changed'));
      list.height = 80;
      expect(
        geometry.rememberPostExtent(41, post: edited, snapshot: changedTopic),
        isTrue,
      );
      expect(
        geometry.minimumHeightFor(41, post: edited, snapshot: changedTopic),
        80,
      );
      geometry.clear();
      expect(
        geometry.minimumHeightFor(41, post: edited, snapshot: changedTopic),
        isNull,
      );
    },
  );

  test('estimated, missing and detached measurements are never retained', () {
    final list = _MeasuredList();
    final geometry = _geometry(list);
    const post = Post(
      id: 41,
      postNumber: 1,
      username: 'reader',
      cooked: '<p>A</p>',
    );
    final snapshot = _snapshot(
      const TopicDetail(id: 1, title: 'Topic', stream: [41]),
    );
    expect(
      geometry.rememberPostExtent(41, post: post, snapshot: snapshot),
      isFalse,
    );
    geometry.applyWindowChange(_windowChange(const [], const [41]));
    list.estimated = true;
    expect(
      geometry.rememberPostExtent(41, post: post, snapshot: snapshot),
      isFalse,
    );
    list.estimated = false;
    list.attached = false;
    expect(
      geometry.rememberPostExtent(41, post: post, snapshot: snapshot),
      isFalse,
    );
    list.attached = true;
    expect(
      geometry.rememberPostExtent(41, post: post, snapshot: _snapshot(null)),
      isFalse,
    );
    expect(
      geometry.minimumHeightFor(41, post: post, snapshot: snapshot),
      isNull,
    );
  });

  for (final hasHeader in [false, true]) {
    test(
      'post and separator keys share one mapping with header=$hasHeader',
      () {
        final window = TopicPostWindow([41, 42, 43], hasHeader: hasHeader);
        final first = hasHeader ? 2 : 0;
        expect(window.childIndexForKey(const ValueKey(41)), first);
        expect(window.childIndexForKey(const ValueKey(42)), first + 2);
        expect(window.childIndexForKey(const ValueKey(43)), first + 4);
        expect(window.childIndexForKey(const ValueKey(99)), isNull);
        expect(window.childIndexForKey(const ValueKey('unknown')), isNull);
        expect(
          window.childIndexForKey(const ValueKey(('topic-post-separator', 41))),
          hasHeader ? 1 : null,
        );
        expect(
          window.childIndexForKey(const ValueKey(('topic-post-separator', 42))),
          first + 1,
        );
        expect(
          window.childIndexForKey(
            const ValueKey(('topic-trailing-separator', 0)),
          ),
          first + 5,
        );
        expect(window.postIndexesInRange((0, first + 6)), [0, 1, 2]);
        expect(window.postIndexesInRange((0, first + 6), reverse: true), [
          2,
          1,
          0,
        ]);
        expect(window.postIndexesInRange(null), isEmpty);
      },
    );
  }

  test('separator identity follows its next post through a prepend', () {
    final before = TopicPostWindow([41, 42], hasHeader: true);
    final after = TopicPostWindow([39, 40, 41, 42], hasHeader: false);
    final separator = before.separatorKeyAfterItem(0);
    expect(separator, const ValueKey(('topic-post-separator', 41)));
    expect(after.separatorKeyAfterItem(1), separator);
    expect(before.childIndexForKey(separator), 1);
    expect(after.childIndexForKey(separator), 3);
    expect(before.childIndexForKey(const ValueKey(41)), 2);
    expect(after.childIndexForKey(const ValueKey(41)), 4);
    expect(after.postIndexesInRange((3, 5)), [2]);
  });

  test('loading placeholders do not become visible post anchors', () {
    final window = TopicPostWindow([61, 62], hasHeader: true);
    expect(window.postIndexesInRange((0, 1)), isEmpty);
    expect(window.postIndexesInRange((5, 6)), isEmpty);
    expect(window.postIndexesInRange((1, 3)), [0]);
    expect(
      window.separatorKeyAfterItem(2),
      const ValueKey(('topic-trailing-separator', 0)),
    );
  });
}

TopicReaderGeometry _geometry(_MeasuredList list) => TopicReaderGeometry(
  scrollController: () => null,
  listController: () => list,
  topInset: () => 0,
  startsAtBeginning: () => false,
  postFrame: (_) {},
)..postWidth = 400;

TopicViewportWindowChange _windowChange(
  List<int> previous,
  List<int> current,
) => TopicViewportWindowChange(
  extentAction: TopicViewportExtentAction.replace,
  previousPostIds: previous,
  currentPostIds: current,
  previousHasHeader: false,
  hasHeader: false,
  prepended: false,
  appendOnly: false,
);

TopicViewportSnapshot _snapshot(
  TopicDetail? topic, {
  bool summary = false,
  bool summaryLoading = false,
  int readTimeWordCount = 0,
}) => TopicViewportSnapshot(
  topicId: 1,
  topic: topic,
  siteUrl: 'https://example.com',
  postIds: const [41],
  streamIds: const [41],
  loading: false,
  loadingMore: false,
  loadingEarlier: false,
  hasMore: false,
  hasEarlier: false,
  initialPostIndex: null,
  recommendations: null,
  summary: summary,
  summaryLoading: summaryLoading,
  readTimeWordCount: readTimeWordCount,
  showTimeGapDays: 0,
  navigationRevision: 0,
);

class _MeasuredList extends Fake implements ListController {
  double height = 800;
  bool estimated = false;
  bool attached = true;

  @override
  bool get isAttached => attached;

  @override
  int get numberOfItems => 1;

  @override
  (double, bool) extentForIndex(int index) => (height, estimated);
}
