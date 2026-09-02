import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Opens a topic whose stream is [streamLength] posts long with the first
/// [loaded] of them in the store, and a saved reading position inside the
/// window so the snapshot also resolves the initial post.
Future<ShellController> _openTopic({
  required int streamLength,
  required int loaded,
}) async {
  final posts = [
    for (var i = 1; i <= loaded; i++)
      Post(id: i, postNumber: i, username: 'author', cooked: '<p>$i</p>'),
  ];
  final api = FakeDiscourseApi(
    feeds: const {
      '/latest.json': [Topic(id: 7, title: 'Long', slug: 'long')],
    },
    topics: {
      7: topicPayload(
        id: 7,
        title: 'Long',
        posts: posts,
        stream: [for (var i = 1; i <= streamLength; i++) i],
      ),
    },
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(
      topicId: 7,
      slug: 'long',
      title: 'Long',
      postNumber: loaded ~/ 2,
    ),
  );
  await controller.loadTopic(7, 'long');
  expect(controller.currentPostIds, hasLength(loaded));
  expect(controller.currentTopicHasMore, isTrue);
  return controller;
}

Duration _timeSnapshots(ShellController controller) {
  var best = const Duration(days: 1);
  for (var round = 0; round < 5; round++) {
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      TopicViewportSnapshot.from(controller);
    }
    stopwatch.stop();
    if (stopwatch.elapsed < best) best = stopwatch.elapsed;
  }
  return best;
}

void main() {
  // The open topic's viewport selector rebuilds this snapshot on every shell
  // notification. The loaded window is bounded by the store policy; the
  // stream is not, so the snapshot must not walk it.
  test(
    'the viewport snapshot costs the loaded window, not the whole stream',
    () async {
      final short = await _openTopic(streamLength: 2000, loaded: 200);
      final long = await _openTopic(streamLength: 16000, loaded: 200);
      expect(
        TopicViewportSnapshot.from(long).initialPostIndex,
        isNotNull,
        reason: 'the saved position must be resolved for the cost to count',
      );

      final shortCost = _timeSnapshots(short);
      final longCost = _timeSnapshots(long);

      expect(
        longCost.inMicroseconds,
        lessThan(shortCost.inMicroseconds * 3),
        reason:
            'an eightfold stream cost ${longCost.inMicroseconds}µs against '
            '${shortCost.inMicroseconds}µs',
      );
    },
  );
}
