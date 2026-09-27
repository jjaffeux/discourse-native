import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _topicId = 7;
const _originalKey = 'original-key';
const _originalUser = DiscourseUser(id: 7, username: 'original', staff: true);
const _replacementUser = DiscourseUser(
  id: 8,
  username: 'replacement',
  staff: true,
);
const _author = DiscourseUser(id: 3, username: 'author');

enum _Action { pin, closed, archived, visible, delete, recover }

enum _Completion { success, refusal, failure }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in _Action.values) {
    group(action.name, () {
      for (final completion in _Completion.values) {
        test(
          'retired $completion cannot release a replacement write lock',
          () async {
            final (:shell, :api) = await _fixture(action);
            final oldWrite = _write(shell, action, true);
            await api.waitForWrites(1);
            expect(_busy(shell, action), isTrue);

            await shell.disconnectCurrentInstance();
            await shell.connectCurrentInstance();
            await shell.loadFeed('latest');
            await shell.loadTopic(_topicId, 'topic');
            expect(shell.currentInstance?.user, _replacementUser);
            expect(_busy(shell, action), isFalse);

            final replacementWrite = _write(shell, action, true);
            await api.waitForWrites(2);
            await pumpEventQueue();
            expect(_busy(shell, action), isTrue);
            expect(api.writes.map((write) => write.apiKey), [
              _originalKey,
              'api-key',
            ]);
            expect(
              api.writes.map((write) => (write.siteUrl, write.topicId)),
              everyElement((_siteUrl, _topicId)),
            );
            final replacementTopic = shell.store.read<TopicDetail>(
              _siteUrl,
              _topicId,
            );
            final replacementRow = shell.store.read<Topic>(_siteUrl, _topicId);
            var notifications = 0;
            void listener() => notifications++;
            shell.addListener(listener);

            _complete(api.writes.first.result, completion);
            expect(await oldWrite, _result(completion));

            // A stale success must not project into the new account, and a
            // stale pin failure must not roll its optimistic state back.
            expect(
              shell.store.read<TopicDetail>(_siteUrl, _topicId),
              same(replacementTopic),
            );
            expect(
              shell.store.read<Topic>(_siteUrl, _topicId),
              same(replacementRow),
            );
            expect(_busy(shell, action), isTrue);
            expect(notifications, 0);
            shell.removeListener(listener);

            // Pin is optimistic, so request the opposite value to exercise
            // admission rather than the already-pinned no-op.
            expect(
              await _write(shell, action, action != _Action.pin),
              _busyMessage(action),
            );
            expect(api.writes, hasLength(2));
            expect(_busy(shell, action), isTrue);

            _complete(api.writes.last.result, completion);
            expect(await replacementWrite, _result(completion));
            expect(_busy(shell, action), isFalse);
            _expectState(shell, action, completion == _Completion.success);

            final retry = _write(
              shell,
              action,
              completion != _Completion.success,
            );
            await api.waitForWrites(3);
            expect(_busy(shell, action), isTrue);
            expect(api.writes.last.apiKey, 'api-key');
            api.writes.last.result.complete();
            expect(await retry, isNull);
            expect(_busy(shell, action), isFalse);
            _expectState(shell, action, completion != _Completion.success);
          },
        );

        test('current account releases its lock after $completion', () async {
          final (:shell, :api) = await _fixture(action);
          final writing = _write(shell, action, true);
          await api.waitForWrites(1);
          expect(_busy(shell, action), isTrue);
          _expectState(shell, action, action == _Action.pin);
          expect(
            await _write(shell, action, action != _Action.pin),
            _busyMessage(action),
          );
          expect(api.writes, hasLength(1));

          _complete(api.writes.single.result, completion);
          expect(await writing, _result(completion));
          expect(_busy(shell, action), isFalse);
          _expectState(shell, action, completion == _Completion.success);
        });
      }

      test('refuses an action without its topic permission', () async {
        final (:shell, :api) = await _fixture(action);
        shell.store.put(
          _siteUrl,
          topicPayload(
            id: _topicId,
            visible: false,
            deletedAt: action == _Action.recover ? DateTime.utc(2026) : null,
          ).detail,
        );

        expect(await _write(shell, action, true), isNotNull);
        expect(api.writes, isEmpty);
        expect(_busy(shell, action), isFalse);
      });
    });
  }

  // A pin change is optimistic and holds only its own lock: the reader keeps
  // reading and a moderator can close the topic while it is in flight. Taking
  // it back must take back only its own guess.
  group('a rejected pin change', () {
    for (final completion in [_Completion.refusal, _Completion.failure]) {
      test('ending in $completion keeps what changed meanwhile', () async {
        final (:shell, :api) = await _fixture(_Action.pin);
        shell.store.put(
          _siteUrl,
          const Topic(
            id: _topicId,
            title: 'Topic',
            slug: 'topic',
            postsCount: 5,
            highestPostNumber: 5,
            lastReadPostNumber: 1,
            unreadPosts: 4,
          ),
        );
        final pinning = _write(shell, _Action.pin, true);
        await api.waitForWrites(1);
        _expectState(shell, _Action.pin, true);

        await shell.markTopicRead(_siteUrl, _topicId, 5, caughtUp: true);
        final closing = _write(shell, _Action.closed, true);
        await api.waitForWrites(2);
        api.writes.last.result.complete();
        expect(await closing, isNull);

        _complete(api.writes.first.result, completion);
        expect(await pinning, _result(completion));

        _expectState(shell, _Action.pin, false);
        _expectState(shell, _Action.closed, true);
        final row = shell.store.read<Topic>(_siteUrl, _topicId)!;
        expect(row.lastReadPostNumber, 5);
        expect(row.unreadPosts, 0);
      });
    }

    test('leaves a pin the site has since taken away', () async {
      final (:shell, :api) = await _fixture(_Action.pin);
      final pinning = _write(shell, _Action.pin, true);
      await api.waitForWrites(1);

      // Staff unpinned the topic for everyone, so it no longer offers the
      // reader a pin preference to restore.
      api.topics[_topicId] = topicPayload(id: _topicId, title: 'Topic');
      await shell.loadTopic(_topicId, 'topic', force: true);
      _complete(api.writes.single.result, _Completion.refusal);
      expect(await pinning, _result(_Completion.refusal));

      final topic = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
      expect(topic.pinned, isFalse);
      expect(topic.unpinned, isFalse);
      expect(topic.hasPinPreference, isFalse);
    });
  });

  // PostDestroyer#recover also recovers the topic of a first post, and the
  // only topic message it publishes is a stats one.
  group('first post undelete', () {
    for (final completion in _Completion.values) {
      test('the topic follows an undelete that ends in $completion', () async {
        final (:shell, :api) = await _fixture(
          _Action.recover,
          posts: [_deletedPost(1)],
          postsById: {1: _post(1)},
        );
        final undeleting = shell.recoverPost(
          shell.store.read<Post>(_siteUrl, 1)!,
        );
        await api.waitForWrites(1);
        expect(api.recovered, [1]);
        _expectState(shell, _Action.recover, false);

        _complete(api.writes.single.result, completion);
        expect(await undeleting, _result(completion));
        final succeeded = completion == _Completion.success;
        _expectState(shell, _Action.recover, succeeded);
        expect(shell.store.read<Post>(_siteUrl, 1)!.isDeleted, !succeeded);
      });
    }

    test('a retired undelete leaves the replacement topic alone', () async {
      final (:shell, :api) = await _fixture(
        _Action.recover,
        posts: [_deletedPost(1)],
        postsById: {1: _post(1)},
      );
      final oldUndelete = shell.recoverPost(
        shell.store.read<Post>(_siteUrl, 1)!,
      );
      await api.waitForWrites(1);

      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      await shell.loadFeed('latest');
      await shell.loadTopic(_topicId, 'topic');
      expect(shell.currentInstance?.user, _replacementUser);
      final replacementTopic = shell.store.read<TopicDetail>(
        _siteUrl,
        _topicId,
      );
      final replacementPost = shell.store.read<Post>(_siteUrl, 1);

      api.writes.single.result.complete();
      expect(await oldUndelete, isNull);
      expect(
        shell.store.read<TopicDetail>(_siteUrl, _topicId),
        same(replacementTopic),
      );
      expect(shell.store.read<Post>(_siteUrl, 1), same(replacementPost));
      _expectState(shell, _Action.recover, false);
    });

    test('undeleting a reply leaves its topic deleted', () async {
      final (:shell, :api) = await _fixture(
        _Action.recover,
        posts: [_deletedPost(1), _deletedPost(2)],
        postsById: {2: _post(2)},
      );
      final undeleting = shell.recoverPost(
        shell.store.read<Post>(_siteUrl, 2)!,
      );
      await api.waitForWrites(1);
      api.writes.single.result.complete();

      expect(await undeleting, isNull);
      expect(api.recovered, [2]);
      expect(shell.store.read<Post>(_siteUrl, 2)!.isDeleted, isFalse);
      _expectState(shell, _Action.recover, false);
    });
  });

  // Neither endpoint answers with the topic, and PostDestroyer changes more
  // than its deletion: an author who cannot moderate the topic withdraws it
  // (closed, not deleted), and taking that back reopens it.
  group('the topic follows PostDestroyer', () {
    for (final firstPost in [false, true]) {
      final via = firstPost ? 'its first post' : 'the topic';

      test(
        'an author taking back a withdrawal through $via reopens the topic',
        () async {
          final (:shell, :api) = await _fixture(
            _Action.recover,
            user: _author,
            listedClosed: true,
            topic: _topic(
              withdrawn: true,
              closed: true,
              moderator: false,
              posts: [_withdrawnPost],
            ),
            recovered: _topic(
              moderator: false,
              canCreatePost: true,
              posts: [_post(1)],
            ),
            postsById: {1: _post(1)},
          );
          api.readGate = Completer<void>();
          final reads = api.topicsOpened.length;

          final recovering = _recover(shell, firstPost);
          await api.waitForWrites(1);
          api.writes.single.result.complete();
          expect(await recovering, isNull);

          final topic = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
          expect(topic.closed, isFalse);
          expect(shell.store.read<Topic>(_siteUrl, _topicId)!.closed, isFalse);
          expect(topic.deletedAt, isNull);
          expect(topic.canRecoverTopic, isFalse);
          // Whether it takes replies again is only the server's to say.
          await pumpEventQueue();
          expect(api.topicsOpened, hasLength(reads + 1));
          expect(
            shell.store.read<TopicDetail>(_siteUrl, _topicId)!.canCreatePost,
            isFalse,
          );

          api.readGate!.complete();
          await pumpEventQueue();
          final reread = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
          expect(reread.canCreatePost, isTrue);
          expect(reread.closed, isFalse);
        },
      );

      test(
        'staff recovering a closed topic through $via leave it closed',
        () async {
          final (:shell, :api) = await _fixture(
            _Action.recover,
            listedClosed: true,
            topic: _topic(
              deleted: true,
              closed: true,
              posts: [_deletedPost(1)],
            ),
            recovered: _topic(
              closed: true,
              canCreatePost: true,
              posts: [_post(1)],
            ),
            postsById: {1: _post(1)},
          );
          api.readGate = Completer<void>();

          final recovering = _recover(shell, firstPost);
          await api.waitForWrites(1);
          api.writes.single.result.complete();
          expect(await recovering, isNull);

          final topic = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
          expect(topic.deletedAt, isNull);
          expect(topic.closed, isTrue);
          expect(shell.store.read<Topic>(_siteUrl, _topicId)!.closed, isTrue);

          api.readGate!.complete();
          await pumpEventQueue();
          final reread = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
          expect(reread.canCreatePost, isTrue);
          expect(reread.closed, isTrue);
        },
      );
    }

    test('an author deleting a topic withdraws it', () async {
      final (:shell, :api) = await _fixture(
        _Action.delete,
        user: _author,
        topic: _topic(moderator: false, canCreatePost: true, posts: [_post(1)]),
        deleted: _topic(
          withdrawn: true,
          closed: true,
          moderator: false,
          posts: [_withdrawnPost],
        ),
      );
      final reads = api.topicsOpened.length;

      final deleting = shell.setTopicDeleted(_siteUrl, _topicId, true);
      await api.waitForWrites(1);
      api.writes.single.result.complete();
      expect(await deleting, isNull);

      final topic = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
      expect(topic.deletedAt, isNull);
      expect(topic.closed, isTrue);
      expect(shell.store.read<Topic>(_siteUrl, _topicId)!.closed, isTrue);
      expect(topic.canRecoverTopic, isTrue);
      expect(topic.canDeleteTopic, isTrue);

      // Site settings can make the server trash it instead, which the author
      // may no longer read, so the topic is read again when next opened.
      await pumpEventQueue();
      expect(api.topicsOpened, hasLength(reads));
      await shell.loadTopic(_topicId, 'topic');
      expect(api.topicsOpened, hasLength(reads + 1));
      expect(
        shell.store.read<TopicDetail>(_siteUrl, _topicId)!.canCreatePost,
        isFalse,
      );
    });

    test(
      'a moderator deleting a topic trashes it and leaves it open',
      () async {
        final (:shell, :api) = await _fixture(_Action.delete);
        final reads = api.topicsOpened.length;

        final deleting = shell.setTopicDeleted(_siteUrl, _topicId, true);
        await api.waitForWrites(1);
        api.writes.single.result.complete();
        expect(await deleting, isNull);

        final topic = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
        expect(topic.deletedAt, isNotNull);
        expect(topic.closed, isFalse);
        expect(shell.store.read<Topic>(_siteUrl, _topicId)!.closed, isFalse);

        await shell.loadTopic(_topicId, 'topic');
        expect(api.topicsOpened, hasLength(reads + 1));
      },
    );

    test('a read sent before a withdrawal lands is read again', () async {
      final (:shell, :api) = await _fixture(
        _Action.delete,
        user: _author,
        topic: _topic(moderator: false, posts: [_post(1)]),
        deleted: _topic(
          withdrawn: true,
          closed: true,
          moderator: false,
          posts: [_withdrawnPost],
        ),
      );
      final gate = api.readGate = Completer<void>();
      final reading = shell.loadTopic(_topicId, 'topic', force: true);
      await pumpEventQueue();
      final reads = api.topicsOpened.length;

      final deleting = shell.setTopicDeleted(_siteUrl, _topicId, true);
      await api.waitForWrites(1);
      api.writes.single.result.complete();
      expect(await deleting, isNull);
      expect(shell.store.read<TopicDetail>(_siteUrl, _topicId)!.closed, isTrue);

      gate.complete();
      await reading;
      await pumpEventQueue();
      expect(api.topicsOpened, hasLength(reads + 1));
      final topic = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
      expect(topic.closed, isTrue);
      expect(topic.canRecoverTopic, isTrue);
    });
  });
}

Future<String?> _recover(ShellController shell, bool firstPost) => firstPost
    ? shell.recoverPost(shell.store.read<Post>(_siteUrl, 1)!)
    : shell.setTopicDeleted(_siteUrl, _topicId, false);

TopicPayload _topic({
  bool deleted = false,
  bool withdrawn = false,
  bool closed = false,
  bool moderator = true,
  bool canCreatePost = false,
  List<Post> posts = const [],
}) => topicPayload(
  id: _topicId,
  title: 'Topic',
  posts: posts,
  unpinned: true,
  visible: false,
  closed: closed,
  deletedAt: deleted ? DateTime.utc(2026) : null,
  canCreatePost: canCreatePost,
  canCloseTopic: moderator,
  canArchiveTopic: moderator,
  canToggleTopicVisibility: moderator,
  canDeleteTopic: !deleted,
  canRecoverTopic: deleted || withdrawn,
);

// PostDestroyer#mark_for_deletion keeps the post but marks it user_deleted.
const _withdrawnPost = Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: '<p>(topic withdrawn by author)</p>',
  userId: 3,
  userDeleted: true,
  canRecover: true,
);

Post _post(int number) => Post(
  id: number,
  postNumber: number,
  username: 'author',
  cooked: '<p>post $number</p>',
  userId: 3,
);

Post _deletedPost(int number) => Post(
  id: number,
  postNumber: number,
  username: 'author',
  cooked: '<p>post $number</p>',
  userId: 3,
  deletedAt: DateTime.utc(2026),
  canRecover: true,
);

Future<String?> _write(ShellController shell, _Action action, bool enabled) =>
    switch (action) {
      _Action.pin => shell.updateTopicPinPreference(
        _siteUrl,
        _topicId,
        enabled,
      ),
      _Action.closed || _Action.archived || _Action.visible =>
        shell.updateTopicStatus(_siteUrl, _topicId, _status(action), enabled),
      _Action.delete || _Action.recover => shell.setTopicDeleted(
        _siteUrl,
        _topicId,
        action == _Action.delete ? enabled : !enabled,
      ),
    };

TopicStatusProperty _status(_Action action) => switch (action) {
  _Action.closed => TopicStatusProperty.closed,
  _Action.archived => TopicStatusProperty.archived,
  _Action.visible => TopicStatusProperty.visible,
  _ => throw ArgumentError.value(action),
};

bool _busy(ShellController shell, _Action action) => switch (action) {
  _Action.pin => shell.topicPinWriteInFlight(_siteUrl, _topicId),
  _Action.closed ||
  _Action.archived ||
  _Action.visible => shell.topicStatusWriteInFlight(_siteUrl, _topicId),
  _Action.delete ||
  _Action.recover => shell.topicDeletionWriteInFlight(_siteUrl, _topicId),
};

String _busyMessage(_Action action) => action == _Action.pin
    ? 'Another pin change is still finishing.'
    : 'Another topic action is still finishing.';

String? _result(_Completion completion) => switch (completion) {
  _Completion.success => null,
  _Completion.refusal => const WriteException(WriteFailure.forbidden).message,
  _Completion.failure => const WriteException(WriteFailure.unreachable).message,
};

void _complete(Completer<void> response, _Completion completion) {
  switch (completion) {
    case _Completion.success:
      response.complete();
    case _Completion.refusal:
      response.completeError(const WriteException(WriteFailure.forbidden));
    case _Completion.failure:
      response.completeError(StateError('Connection failed'));
  }
}

void _expectState(ShellController shell, _Action action, bool changed) {
  final topic = shell.store.read<TopicDetail>(_siteUrl, _topicId)!;
  final row = shell.store.read<Topic>(_siteUrl, _topicId)!;
  switch (action) {
    case _Action.pin:
      expect(topic.pinned, changed);
      expect(topic.unpinned, !changed);
      expect(row.pinned, changed);
    case _Action.closed || _Action.archived || _Action.visible:
      expect(topic.statusValue(_status(action)), changed);
      if (action == _Action.closed) expect(row.closed, changed);
    case _Action.delete || _Action.recover:
      final deleted = action == _Action.delete ? changed : !changed;
      expect(topic.deletedAt != null, deleted);
      expect(topic.canDeleteTopic, !deleted);
      expect(topic.canRecoverTopic, deleted);
  }
}

/// [topic] is what the site serves at first, and [deleted] and [recovered]
/// what it serves once it accepts a deletion or a recovery.
Future<({ShellController shell, _GatedTopicApi api})> _fixture(
  _Action action, {
  DiscourseUser user = _originalUser,
  bool listedClosed = false,
  List<Post> posts = const [],
  Map<int, Post> postsById = const {},
  TopicPayload? topic,
  TopicPayload? deleted,
  TopicPayload? recovered,
}) async {
  final served =
      topic ?? _topic(deleted: action == _Action.recover, posts: posts);
  final api = _GatedTopicApi(
    served,
    originalUser: user,
    listedClosed: listedClosed,
    deletedTopic: deleted ?? _topic(deleted: true, posts: posts),
    recoveredTopic:
        recovered ??
        _topic(posts: [for (final post in posts) postsById[post.id] ?? post]),
    postsById: postsById,
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = _originalKey,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(() {
    shell.dispose();
    for (final write in api.writes) {
      if (!write.result.isCompleted) write.result.complete();
    }
  });
  await shell.load();
  await shell.loadFeed('latest');
  // Post actions write to the topic on screen.
  if (served.posts.isNotEmpty) {
    shell.pushContent(
      ContentRoute.topic(topicId: _topicId, slug: 'topic', title: 'Topic'),
    );
  }
  await shell.loadTopic(_topicId, 'topic');
  return (shell: shell, api: api);
}

class _GatedTopicApi extends FakeDiscourseApi {
  _GatedTopicApi(
    TopicPayload topic, {
    required this.originalUser,
    required bool listedClosed,
    required this.deletedTopic,
    required this.recoveredTopic,
    super.postsById,
  }) : super(
         feeds: {
           '/latest.json': [
             Topic(
               id: _topicId,
               title: 'Topic',
               slug: 'topic',
               closed: listedClosed,
             ),
           ],
         },
         topics: {_topicId: topic},
       );

  final DiscourseUser originalUser;
  final TopicPayload deletedTopic;
  final TopicPayload recoveredTopic;

  /// Holds topic reads, which answer with what the site served when sent.
  Completer<void>? readGate;

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
    final served = await super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      summary: summary,
      apiKey: apiKey,
      clientId: clientId,
      abortTrigger: abortTrigger,
    );
    await readGate?.future;
    return served;
  }

  final writes =
      <
        ({String siteUrl, String apiKey, int topicId, Completer<void> result})
      >[];
  Completer<void> _writesChanged = Completer<void>();

  Future<void> waitForWrites(int count) async {
    while (writes.length < count) {
      await _writesChanged.future.timeout(const Duration(seconds: 5));
    }
  }

  Future<void> _hold(String siteUrl, String apiKey, int topicId) {
    final result = Completer<void>();
    writes.add((
      siteUrl: siteUrl,
      apiKey: apiKey,
      topicId: topicId,
      result: result,
    ));
    _writesChanged.complete();
    _writesChanged = Completer<void>();
    return result.future;
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => apiKey == _originalKey ? originalUser : _replacementUser;

  @override
  Future<void> updateTopicPinForUser({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool pinned,
    String? clientId,
  }) => _hold(siteUrl, apiKey, topicId);

  @override
  Future<void> updateTopicStatus({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicStatusProperty status,
    required bool enabled,
    String? clientId,
  }) => _hold(siteUrl, apiKey, topicId);

  @override
  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    await _hold(siteUrl, apiKey, topicId);
    topics[_topicId] = deletedTopic;
  }

  @override
  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    await _hold(siteUrl, apiKey, topicId);
    topics[_topicId] = recoveredTopic;
  }

  @override
  Future<void> recoverPost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    await super.recoverPost(
      siteUrl: siteUrl,
      apiKey: apiKey,
      postId: postId,
      clientId: clientId,
    );
    await _hold(siteUrl, apiKey, _topicId);
    // Recovering the first post recovers its topic.
    if (postId == 1) topics[_topicId] = recoveredTopic;
  }
}
