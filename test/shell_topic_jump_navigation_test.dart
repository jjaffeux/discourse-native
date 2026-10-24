import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _reader = DiscourseUser(id: 7, username: 'reader');
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

const _megaTail = (
  detail: TopicDetail(
    id: 1,
    title: 'One',
    stream: [200, 300],
    postsCount: 3,
    isMegaTopic: true,
    lastPostId: 300,
    highestPostNumber: 12,
  ),
  posts: [_secondPost, _lastPost],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('topic jump navigation ownership', () {
    for (final suffix in ['last', '99999999']) {
      for (final cold in [false, true]) {
        test(
          '$suffix opens the final visible post ${cold ? 'from another page' : 'in place'}',
          () async {
            final (:shell, :api, authenticator: _) = await _fixture();
            shell.openCurrentTopicPost(2);
            await pumpEventQueue();
            shell.saveTopicScrollPost(1, 2, viewportOffset: -48);
            if (cold) {
              shell.createTab();
              shell.store.remove<TopicDetail>(_siteUrl, 1);
              expect(shell.store.read<TopicDetail>(_siteUrl, 1), isNull);
            }
            final revision = shell.topicNavigationRevision;
            expect(shell.openTopicUrl('$_siteUrl/t/one/1/$suffix'), isTrue);
            await pumpEventQueue();
            expect(shell.currentContent?.postNumber, 12);
            expect(shell.topicScrollPostNumber(1), 12);
            expect(shell.currentContent?.id, 'topic-1');
            expect(shell.activeTab!.anchors[shell.currentContent!.id], isNull);
            if (!cold) expect(shell.topicNavigationRevision, revision + 1);
            expect(api.topicPostNumbersOpened, [2, 99999999]);
            await shell.loadTopic(1, 'one');
            expect(api.topicPostNumbersOpened, [2, 99999999]);
          },
        );
      }
    }

    test(
      'a cached complete topic settles last without an impossible fetch',
      () async {
        final (:shell, :api, authenticator: _) = await _fixture();
        shell.store.put(_siteUrl, _lastPost);
        expect(shell.openTopicUrl('$_siteUrl/t/1/last'), isTrue);
        await pumpEventQueue();
        expect(shell.currentContent?.postNumber, 12);
        expect(api.topicPostNumbersOpened, isEmpty);
      },
    );

    test(
      'settling last preserves a topic route identity and retained feed path',
      () async {
        final (:shell, api: _, authenticator: _) = await _fixture();
        final route = shell.currentContent!;
        shell.replaceCurrentContent(
          ContentRoute(
            destination: const TopicDestination(
              topicId: 1,
              slug: 'one',
              legacyKey: 'saved-topic',
              retainedFeedPath: '/latest.json',
            ),
            title: route.title,
            icon: route.icon,
            subtitle: 'Saved subtitle',
          ),
        );
        expect(shell.openTopicUrl('$_siteUrl/t/1/last'), isTrue);
        await pumpEventQueue();
        expect(shell.currentContent?.postNumber, 12);
        expect(shell.currentContent?.id, 'saved-topic');
        expect(shell.currentContent?.feedPath, '/latest.json');
        expect(shell.currentContent?.subtitle, 'Saved subtitle');
      },
    );

    test('a partial mega-topic cache cannot supply the final post', () async {
      final (:shell, :api, authenticator: _) = await _fixture();
      api.finalPayload = _megaTail;
      shell.store.remove<TopicDetail>(_siteUrl, 1);
      shell.store.put(
        _siteUrl,
        const TopicDetail(
          id: 1,
          title: 'One',
          stream: [100],
          isMegaTopic: true,
          highestPostNumber: 12,
          lastPostId: 300,
        ),
      );
      expect(shell.focusedTabContext.currentPostIds, [100]);
      expect(shell.openTopicUrl('$_siteUrl/t/1/last'), isTrue);
      await pumpEventQueue();
      expect(shell.currentContent?.postNumber, 12);
      expect(shell.focusedTabContext.currentTopic?.isMegaTopic, isTrue);
      expect(shell.focusedTabContext.currentPostIds, contains(300));
      expect(api.topicPostNumbersOpened, [99999999]);
    });

    test(
      'a cached final post outside a mega-topic run still loads the tail',
      () async {
        final (:shell, :api, authenticator: _) = await _fixture();
        api.finalPayload = _megaTail;
        shell.store.remove<TopicDetail>(_siteUrl, 1);
        shell.store
          ..put(_siteUrl, _lastPost)
          ..put(
            _siteUrl,
            const TopicDetail(
              id: 1,
              title: 'One',
              stream: [100],
              isMegaTopic: true,
              lastPostId: 300,
              highestPostNumber: 12,
            ),
          );
        expect(shell.store.read<TopicDetail>(_siteUrl, 1)?.stream, [100]);
        expect(shell.store.read<Post>(_siteUrl, 300)?.postNumber, 12);
        expect(shell.focusedTabContext.currentPostIds, [100]);
        expect(shell.openTopicUrl('$_siteUrl/t/1/last'), isTrue);
        await pumpEventQueue();
        expect(api.topicPostNumbersOpened, [99999999]);
        expect(shell.currentContent?.postNumber, 12);
        expect(shell.focusedTabContext.currentTopic?.isMegaTopic, isTrue);
        expect(shell.focusedTabContext.currentPostIds, contains(300));
      },
    );

    test(
      'an empty accepted topic settles last to its opening position',
      () async {
        final (:shell, :api, authenticator: _) = await _fixture();
        api.finalPayload = (
          detail: const TopicDetail(id: 1, title: 'One', stream: []),
          posts: const [],
        );
        expect(shell.openTopicUrl('$_siteUrl/t/1/last'), isTrue);
        await pumpEventQueue();
        expect(shell.currentContent?.postNumber, 1);
        await shell.loadTopic(1, 'one');
        expect(
          api.topicPostNumbersOpened.where((number) => number == 99999999),
          [99999999],
        );
      },
    );

    test('a queued last request settles after the older topic read', () async {
      final (:shell, :api, authenticator: _) = await _fixture();
      final gate = api.gateTopic(2);
      shell.openCurrentTopicPost(2);
      await gate.started.future.timeout(const Duration(seconds: 2));
      expect(shell.openTopicUrl('$_siteUrl/t/1/last'), isTrue);
      gate.release.complete();
      await pumpEventQueue();
      expect(shell.currentContent?.postNumber, 12);
      expect(api.topicPostNumbersOpened, [2, 99999999]);
    });

    test(
      'an older last response cannot replace a newer explicit target',
      () async {
        final (:shell, :api, authenticator: _) = await _fixture();
        final gate = api.gateTopic(99999999);
        expect(shell.openTopicUrl('$_siteUrl/t/1/last'), isTrue);
        await gate.started.future.timeout(const Duration(seconds: 2));
        shell.openCurrentTopicPost(1);
        final revision = shell.topicNavigationRevision;
        shell.saveTopicScrollPost(1, 1, viewportOffset: -24);
        gate.release.complete();
        await pumpEventQueue();
        expect(shell.currentContent?.postNumber, 1);
        expect(shell.topicScrollPostOffset(1), -24);
        expect(shell.topicNavigationRevision, revision);
      },
    );

    test('a last response cannot settle a retired account', () async {
      final (:shell, :api, authenticator: _) = await _fixture();
      final gate = api.gateTopic(99999999);
      expect(shell.openTopicUrl('$_siteUrl/t/1/last'), isTrue);
      await gate.started.future.timeout(const Duration(seconds: 2));
      expect(await shell.removeInstance(shell.currentInstance!), isTrue);
      gate.release.complete();
      await pumpEventQueue();
      expect(shell.currentInstance, isNull);
      expect(shell.store.read<Post>(_siteUrl, 300), isNull);
    });

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

    for (final returnToOrigin in [false, true]) {
      test(
        'a pending jump after a tab switch '
        '${returnToOrigin ? 'can finish on return' : 'cannot target the other tab'}',
        () async {
          final (:shell, :api, authenticator: _) = await _fixture();
          shell.openCurrentTopicPost(1);
          await pumpEventQueue();
          api.topicPostNumbersOpened.clear();
          final origin = shell.activeTabId!;
          final lookup = api.gatePost(300);
          final pending = shell.jumpToCurrentTopicIndex(3);
          await lookup.started.future;
          shell.createTab();
          expect(shell.activeTabId, isNot(origin));
          if (returnToOrigin) {
            shell.selectTab(origin);
            expect(shell.activeTabId, origin);
          }
          lookup.release.complete();

          expect(await pending, returnToOrigin);
          await pumpEventQueue();
          expect(api.topicPostNumbersOpened, [if (returnToOrigin) 12]);
          if (!returnToOrigin) {
            shell.selectTab(origin);
            expect(shell.currentContent?.postNumber, 1);
            expect(shell.store.read<Post>(_siteUrl, 300), isNull);
          }
        },
      );
    }

    test(
      'a newer jump in another tab supersedes the same-topic attempt',
      () async {
        final (:shell, :api, authenticator: _) = await _fixture();
        shell.openCurrentTopicPost(1);
        await pumpEventQueue();
        final origin = shell.activeTabId!;
        final lookup = api.gatePost(300);
        final pending = shell.jumpToCurrentTopicIndex(3);
        await lookup.started.future;
        shell.createTab();
        shell.pushContent(
          ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
        );
        expect(await shell.jumpToCurrentTopicIndex(1), isTrue);
        shell.selectTab(origin);
        lookup.release.complete();
        expect(await pending, isFalse);
        await pumpEventQueue();
        expect(shell.currentContent?.postNumber, 1);
        expect(shell.store.read<Post>(_siteUrl, 300), isNull);
      },
    );

    testWidgets(
      'an expired pending highlight cannot arm on a later publication',
      (tester) async {
        final fixture = await tester.runAsync(_fixture);
        final shell = fixture!.shell;
        shell.openTopicPost(
          siteUrl: _siteUrl,
          topicId: 1,
          postNumber: 12,
          highlight: true,
        );
        await tester.runAsync(() async => pumpEventQueue());
        expect(shell.isTopicPostHighlighted(_siteUrl, 1, 12), isFalse);
        await tester.pump(const Duration(seconds: 30));
        shell.store.put(_siteUrl, _lastPost);
        await tester.runAsync(() => shell.loadTopic(1, 'one', force: true));
        expect(shell.isTopicPostHighlighted(_siteUrl, 1, 12), isFalse);
      },
    );

    test(
      'mega topic progress targets a post number beyond the held stream',
      () async {
        final (:shell, :api, authenticator: _) = await _fixture();
        shell.store.put(
          _siteUrl,
          const TopicDetail(
            id: 1,
            title: 'One',
            stream: [100, 200, 300],
            postsCount: 9000,
            highestPostNumber: 12000,
            isMegaTopic: true,
          ),
        );
        expect(await shell.jumpToCurrentTopicIndex(8000), isTrue);
        await pumpEventQueue();
        expect(shell.currentContent?.postNumber, 8000);
        expect(api.postFetches, isEmpty);
        expect(api.topicPostNumbersOpened, [8000]);
      },
    );

    testWidgets('one highlight keeps aging while its tab is unfocused', (
      tester,
    ) async {
      final fixture = await tester.runAsync(_fixture);
      final shell = fixture!.shell;
      await tester.pump();
      final origin = shell.activeTabId!;
      shell.openTopicPost(
        siteUrl: _siteUrl,
        topicId: 1,
        postNumber: 1,
        highlight: true,
      );
      expect(shell.isTopicPostHighlighted(_siteUrl, 1, 1), isTrue);
      await tester.runAsync(() async => pumpEventQueue());
      shell.createTab();
      shell.selectTab(origin);
      expect(shell.activeTabId, origin);
      expect(shell.isTopicPostHighlighted(_siteUrl, 1, 1), isTrue);
      shell.createTab();
      expect(shell.isTopicPostHighlighted(_siteUrl, 1, 1), isFalse);
      await tester.pump(const Duration(milliseconds: 1000));
      shell.selectTab(origin);
      expect(shell.activeTabId, origin);
      expect(shell.isTopicPostHighlighted(_siteUrl, 1, 1), isTrue);
      shell.createTab();
      await tester.pump(const Duration(milliseconds: 1200));
      shell.selectTab(origin);
      expect(shell.isTopicPostHighlighted(_siteUrl, 1, 1), isFalse);
      await tester.runAsync(() async => pumpEventQueue());
    });

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

    for (final (postNumber, loaded) in [(1, true), (12, false)]) {
      test('a link to ${loaded ? 'a loaded' : 'an unloaded'} post of the open '
          'topic jumps to it in place', () async {
        final (:shell, :api, authenticator: _) = await _fixture();
        shell.saveTopicScrollPost(1, 2, viewportOffset: -48);
        final revision = shell.topicNavigationRevision;
        final stackLength = shell.contentStack.length;

        expect(shell.openTopicUrl('$_siteUrl/t/one/1/$postNumber'), isTrue);
        await pumpEventQueue();

        expect(shell.currentContent?.topicId, 1);
        expect(shell.currentContent?.postNumber, postNumber);
        expect(shell.contentStack, hasLength(stackLength));
        expect(shell.topicNavigationRevision, revision + 1);
        expect(shell.activeTab!.anchors[shell.currentContent!.id], isNull);
        expect(shell.topicScrollPostNumber(1), postNumber);
        // Unlike a notification, a link reports nothing new about a post the
        // store already holds, so only an unloaded target is fetched.
        expect(api.topicPostNumbersOpened, [if (!loaded) postNumber]);
      });
    }

    test('a bare link to the open topic keeps the reading position', () async {
      final (:shell, :api, authenticator: _) = await _fixture();
      shell.saveTopicScrollPost(1, 2, viewportOffset: -48);
      final route = shell.currentContent;
      final anchor = shell.activeTab!.anchors[route!.id];
      final revision = shell.topicNavigationRevision;
      final stackLength = shell.contentStack.length;

      expect(shell.openTopicUrl('$_siteUrl/t/one/1'), isTrue);
      await pumpEventQueue();

      expect(shell.currentContent, same(route));
      expect(shell.contentStack, hasLength(stackLength));
      expect(shell.topicNavigationRevision, revision);
      expect(shell.activeTab!.anchors[route.id], same(anchor));
      expect(shell.topicScrollPostNumber(1), 2);
      expect(api.topicPostNumbersOpened, isEmpty);
    });

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
  // Only a signed-in forum reads its stored key, so a gated lookup is reached.
  final authenticator = _GatedAuthenticator()..keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: _reader),
    ]),
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
  expect(shell.currentWorkspace!.accountIdentity, shell.currentAccountIdentity);
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
        user: _reader,
        feeds: const {'/latest.json': []},
        topics: const {
          1: (detail: _topic, posts: [_firstPost, _secondPost]),
        },
        postsById: const {200: _secondPost, 300: _lastPost},
      );

  TopicPayload finalPayload = (
    detail: _topic,
    posts: const [_secondPost, _lastPost],
  );
  final _topicGates = <int, _Gate>{};
  _Gate gateTopic(int number) => _topicGates[number] = _Gate();

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    final gate = _topicGates.remove(postNumber);
    if (postNumber == 99999999) {
      topicsOpened.add(id);
      topicPostNumbersOpened.add(postNumber);
      if (gate != null) {
        gate.started.complete();
        await gate.release.future;
      }
      return finalPayload;
    }
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
      abortTrigger: abortTrigger,
    );
  }

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
