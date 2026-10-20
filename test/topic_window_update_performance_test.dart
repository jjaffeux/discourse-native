import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

final class _CountingStore extends Store {
  int postReads = 0;

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) postReads++;
    return super.read<T>(siteUrl, id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('late loaded window remains correct after post updates', () async {
    final reports = <Map<String, Object?>>[];
    for (final streamLength in [2000, 16000]) {
      final start = streamLength - 300;
      final store = _CountingStore();
      final site = instance('scroll.example');
      final posts = [
        for (var id = start; id < start + 200; id++)
          Post(
            id: id,
            postNumber: id,
            username: 'reader',
            cooked: '<p>Reply $id</p>',
          ),
      ];
      final api = FakeDiscourseApi(
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Long',
            posts: posts,
            stream: [for (var id = 1; id <= streamLength; id++) id],
            postsCount: streamLength,
          ),
        },
      );
      final shell = ShellController(
        store: store,
        instanceStore: FakeInstanceStore([site]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'long',
          title: 'Long',
          postNumber: start + 70,
        ),
      );
      await shell.loadTopic(7, 'long', postNumber: start + 70);
      final expected = posts.map((p) => p.id).toList();
      expect(shell.currentPostIds, expected);
      final samples = <int>[];
      for (var round = 0; round < 6; round++) {
        store.postReads = 0;
        var resolved = 0;
        final clock = Stopwatch()..start();
        for (var repeat = 0; repeat < 200; repeat++) {
          store.put(
            site.url,
            Post(
              id: start + 100,
              postNumber: start + 100,
              username: 'reader',
              cooked: '<p>Update $round $repeat</p>',
            ),
          );
          final snapshot = TopicViewportSnapshot.from(shell);
          resolved += snapshot.postIds.length;
          if (snapshot.postIds.first != expected.first ||
              snapshot.postIds.last != expected.last ||
              snapshot.initialPostIndex == null) {
            fail('Loaded window or saved position changed');
          }
        }
        clock.stop();
        expect(resolved, 40000);
        if (round > 0) samples.add(clock.elapsedMicroseconds);
      }
      expect(shell.currentPostIds, expected);
      reports.add({
        'streamLength': streamLength,
        'loaded': 200,
        'updatesPerSample': 200,
        'microseconds': samples,
        'postReadsLastSample': store.postReads,
        'errors': 0,
      });
    }
    final encoded = jsonEncode(reports);
    debugPrint('TOPIC_WINDOW_UPDATE_PROFILE $encoded', wrapWidth: 2048);
    final output = Platform.environment['TOPIC_WINDOW_BENCHMARK_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(encoded);
  });
}
