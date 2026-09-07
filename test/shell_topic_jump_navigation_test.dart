import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _topic = TopicDetail(
  id: 1,
  title: 'One',
  stream: [100, 200, 300],
  postsCount: 3,
);
const _firstPost = Post(
  id: 100,
  postNumber: 1,
  username: 'sam',
  cooked: '<p>First</p>',
);
const _secondPost = Post(
  id: 200,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Second</p>',
);
const _lastPost = Post(
  id: 300,
  postNumber: 12,
  username: 'sam',
  cooked: '<p>Last</p>',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('topic jump navigation ownership', () {
    for (final stage in ['credential', 'post lookup']) {
      for (final navigation in ['direct', 'search']) {
        test(
          '$navigation navigation supersedes a jump during its $stage',
          () async {
            final (:shell, :api, :authenticator) = await _fixture();
            final gate = stage == 'credential'
                ? authenticator.gateNextApiKey()
                : api.gatePost(300);
            final pending = shell.jumpToCurrentTopicIndex(3);
            await gate.started.future;

            final originalRevision = shell.topicNavigationRevision;
            if (navigation == 'direct') {
              shell.openCurrentTopicPost(2);
            } else {
              shell.openSearchResult(
                const SearchPostHit(
                  postId: 200,
                  topicId: 1,
                  postNumber: 2,
                  topicTitle: 'One',
                  topicSlug: 'one',
                  username: 'sam',
                  excerpt: SearchExcerpt([SearchExcerptSegment('Second')]),
                ),
              );
            }
            await pumpEventQueue();
            expect(shell.currentContent?.postNumber, 2);
            expect(api.topicPostNumbersOpened, [2]);
            final revision = shell.topicNavigationRevision;
            expect(revision, originalRevision + 1);
            shell.saveTopicScrollPost(1, 2, viewportOffset: -48);
            final anchor = shell.activeTab!.anchors[shell.currentContent!.id];
            expect(anchor, isNotNull);

            gate.release.complete();

            expect(await pending, isFalse);
            await pumpEventQueue();
            expect(shell.currentContent?.postNumber, 2);
            expect(shell.topicNavigationRevision, revision);
            expect(
              shell.activeTab!.anchors[shell.currentContent!.id],
              same(anchor),
            );
            expect(shell.topicScrollPostNumber(1), 2);
            expect(shell.topicScrollPostOffset(1), -48);
            expect(api.topicPostNumbersOpened, [2]);
            expect(api.postFetches, [
              if (stage == 'post lookup') [300],
            ]);
            expect(shell.store.read<Post>(_siteUrl, 300), isNull);
          },
        );
      }
    }

    test(
      'the current jump resolves an unloaded ID and loads around it',
      () async {
        final (:shell, :api, :authenticator) = await _fixture();
        final credential = authenticator.gateNextApiKey();
        final lookup = api.gatePost(300);
        final revision = shell.topicNavigationRevision;

        final pending = shell.jumpToCurrentTopicIndex(3);
        await credential.started.future;
        expect(api.postFetches, isEmpty);
        credential.release.complete();
        await lookup.started.future;
        // Saving a viewport position does not supersede an explicit jump.
        shell.saveTopicScrollPost(1, 1, viewportOffset: -24);
        lookup.release.complete();

        expect(await pending, isTrue);
        await pumpEventQueue();
        expect(shell.currentContent?.postNumber, 12);
        expect(shell.topicNavigationRevision, revision + 1);
        expect(shell.activeTab!.anchors[shell.currentContent!.id], isNull);
        expect(shell.topicScrollPostNumber(1), 12);
        expect(shell.store.read<Post>(_siteUrl, 300)?.postNumber, 12);
        expect(api.postFetches, [
          [300],
        ]);
        expect(api.topicPostNumbersOpened, [12]);
      },
    );

    for (final olderFinishesFirst in [true, false]) {
      test('the newer jump wins when the older lookup finishes '
          '${olderFinishesFirst ? 'first' : 'last'}', () async {
        final (:shell, :api, authenticator: _) = await _fixture();
        final olderLookup = api.gatePost(300);
        final newerLookup = api.gatePost(200);
        final revision = shell.topicNavigationRevision;
        final older = shell.jumpToCurrentTopicIndex(3);
        await olderLookup.started.future;
        final newer = shell.jumpToCurrentTopicIndex(2);
        await newerLookup.started.future;

        if (olderFinishesFirst) {
          olderLookup.release.complete();
          expect(await older, isFalse);
          expect(shell.topicNavigationRevision, revision);
          expect(api.topicPostNumbersOpened, isEmpty);
        }

        newerLookup.release.complete();
        expect(await newer, isTrue);
        await pumpEventQueue();
        shell.saveTopicScrollPost(1, 2, viewportOffset: -48);
        final anchor = shell.activeTab!.anchors[shell.currentContent!.id];
        if (!olderFinishesFirst) {
          olderLookup.release.complete();
          expect(await older, isFalse);
          await pumpEventQueue();
        }

        expect(shell.currentContent?.postNumber, 2);
        expect(shell.topicNavigationRevision, revision + 1);
        expect(
          shell.activeTab!.anchors[shell.currentContent!.id],
          same(anchor),
        );
        expect(api.postFetches, [
          [300],
          [200],
        ]);
        expect(api.topicPostNumbersOpened, [2]);
        expect(shell.store.read<Post>(_siteUrl, 300), isNull);
      });
    }

    test('a newer loaded jump cancels a pending credential lookup', () async {
      final (:shell, :api, :authenticator) = await _fixture();
      final credential = authenticator.gateNextApiKey();
      final older = shell.jumpToCurrentTopicIndex(3);
      await credential.started.future;

      expect(await shell.jumpToCurrentTopicIndex(1), isTrue);
      final revision = shell.topicNavigationRevision;
      shell.saveTopicScrollPost(1, 1, viewportOffset: -24);
      credential.release.complete();

      expect(await older, isFalse);
      await pumpEventQueue();
      expect(shell.currentContent?.postNumber, 1);
      expect(shell.topicNavigationRevision, revision);
      expect(shell.topicScrollPostNumber(1), 1);
      expect(shell.topicScrollPostOffset(1), -24);
      expect(api.postFetches, isEmpty);
      expect(api.topicPostNumbersOpened, isEmpty);
    });
  });
}

Future<
  ({ShellController shell, _JumpApi api, _GatedAuthenticator authenticator})
>
_fixture() async {
  final api = _JumpApi();
  final authenticator = _GatedAuthenticator();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.example')]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  shell.store
    ..put(_siteUrl, _topic)
    ..put(_siteUrl, _firstPost);
  shell.pushContent(ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'));
  await pumpEventQueue();
  return (shell: shell, api: api, authenticator: authenticator);
}

final class _Gate {
  _Gate() {
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
  }

  final started = Completer<void>();
  final release = Completer<void>();
}

final class _GatedAuthenticator extends FakeAuthenticator {
  _Gate? _gate;

  _Gate gateNextApiKey() => _gate = _Gate();

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    final gate = _gate;
    _gate = null;
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    return super.apiKeyFor(siteUrl);
  }
}

final class _JumpApi extends FakeDiscourseApi {
  _JumpApi()
    : super(
        feeds: const {'/latest.json': []},
        topics: const {
          1: (detail: _topic, posts: [_firstPost, _secondPost]),
        },
        postsById: const {200: _secondPost, 300: _lastPost},
      );

  final _gates = <int, _Gate>{};

  _Gate gatePost(int id) => _gates[id] = _Gate();

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    postFetches.add(List.of(ids));
    final gate = _gates.remove(ids.single);
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    return ids.map((id) => postsById[id]).whereType<Post>().toList();
  }
}
