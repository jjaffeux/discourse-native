import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_controller.dart';
import 'package:discourse_native/src/plugins/poll/poll_data.dart';
import 'package:discourse_native/src/plugins/poll/poll_services.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_controller.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _site2 = 'https://community.example.com';

DiscourseUser _pollUser({
  required int id,
  required String username,
  bool canCreatePoll = true,
  bool staff = false,
  List<String> groups = const [],
}) => DiscourseUser(
  id: id,
  username: username,
  staff: staff,
  groups: groups,
  plugins: PluginData.none.withValue(
    pollCurrentUserDataKey,
    PollCurrentUser(canCreatePoll: canCreatePoll),
  ),
);

final class _GatedCurrentUserApi extends FakeDiscourseApi {
  _GatedCurrentUserApi()
    : super(
        feeds: const {'/latest.json': <Topic>[]},
        siteConfigs: const {_site: SiteConfig.unknown()},
      );

  final response = Completer<DiscourseUser>();
  int calls = 0;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    calls++;
    return response.future;
  }
}

final class _PerSiteCurrentUserApi extends FakeDiscourseApi {
  _PerSiteCurrentUserApi() : super(feeds: const {'/latest.json': <Topic>[]});

  final calls = <String>[];

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    calls.add(siteUrl);
    return _pollUser(
      id: siteUrl == _site ? 1 : 2,
      username: siteUrl == _site ? 'reader' : 'reader2',
      groups: [siteUrl == _site ? 'meta-builders' : 'community-builders'],
    );
  }
}

Poll _poll({
  String name = 'poll',
  int voters = 1,
  int firstVotes = 1,
  List<String> selected = const ['a'],
}) => Poll(
  id: name.hashCode,
  name: name,
  voters: voters,
  options: [
    PollOption(id: 'a', html: 'A', votes: firstVotes),
    PollOption(id: 'b', html: 'B', votes: voters - firstVotes),
  ],
  selection: PollSelection(optionIds: List.unmodifiable(selected)),
);

Post _post({
  Poll? poll,
  Poll? otherPoll,
  Reactions? reactions,
  String cooked = '<p>Initial</p>',
  bool canLike = false,
}) {
  var plugins = PluginData.none;
  if (poll != null) {
    final polls = {poll.name: poll};
    if (otherPoll != null) polls[otherPoll.name] = otherPoll;
    plugins = plugins.withValue(
      pollsDataKey,
      Polls(byName: Map.unmodifiable(polls)),
    );
  }
  if (reactions != null) {
    plugins = plugins.withValue(reactionsDataKey, reactions);
  }
  return Post(
    id: 11,
    postNumber: 2,
    username: 'sam',
    cooked: cooked,
    canLike: canLike || reactions != null,
    plugins: plugins,
  );
}

Future<({ShellController shell, FakeSiteTracker tracker})> _loadShell(
  FakeDiscourseApi api, {
  FakeAuthenticator? authenticator,
}) async {
  authenticator ??= FakeAuthenticator();
  authenticator.keys[_site] = 'api-key';
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  await pumpEventQueue();
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  await shell.loadTopic(7, 'a-topic');
  await pumpEventQueue();
  return (shell: shell, tracker: FakeSiteTracker.built.single);
}

FakeDiscourseApi _api({
  required Post initial,
  Map<String, PollVoteResponse> voteResponses = const {},
  Map<String, PollVoteResponse> removalResponses = const {},
  WriteException? pollFailure,
  Completer<void>? pollGate,
  Completer<void>? postGate,
  Map<int, Post> postsById = const {},
  WriteException? reactionFailure,
  Completer<void>? reactionGate,
}) => FakeDiscourseApi(
  feeds: const {'/latest.json': <Topic>[]},
  topics: {
    7: topicPayload(id: 7, title: 'A topic', posts: [initial]),
  },
  postsById: postsById,
  postGate: postGate,
  siteConfigs: const {_site: SiteConfig.unknown()},
  pollVoteResponses: voteResponses,
  pollRemovalResponses: removalResponses,
  pollVoteFailure: pollFailure,
  pollVoteGate: pollGate,
  reactionFailure: reactionFailure,
  reactionGate: reactionGate,
);

PollVoteResponse _answer(Poll poll) =>
    PollVoteResponse(poll: poll, selection: poll.selection);

PollController _polls(ShellController shell) =>
    shell.pluginSession.require(pollControllerService);

ReactionsController _reactions(ShellController shell) =>
    shell.pluginSession.require(reactionsControllerService);

Future<void> _waitFor(
  bool Function() condition, {
  required String description,
}) async {
  for (var turn = 0; turn < 100; turn++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw TestFailure('Did not observe $description within 100 event turns.');
}

Future<PollVoteWriteResult> _castPollVote(
  ShellController shell,
  Post post,
  Poll poll,
  List<String> optionIds,
) => _polls(shell).castVote(
  siteUrl: _site,
  topicId: 7,
  archived: false,
  post: post,
  poll: poll,
  optionIds: optionIds,
);

Future<PollVoteWriteResult> _removePollVote(
  ShellController shell,
  Post post,
  Poll poll,
) => _polls(shell).removeVote(
  siteUrl: _site,
  topicId: 7,
  archived: false,
  post: post,
  poll: poll,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('session hydration', () {
    test(
      'does not treat persisted account data as fresh session data',
      () async {
        final api = _GatedCurrentUserApi();
        final freshUser = _pollUser(
          id: 1,
          username: 'reader',
          staff: true,
          groups: const ['builders'],
        );
        final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
        final shell = ShellController(
          plugins: installedPlugins,
          instanceStore: FakeInstanceStore([
            instance(
              'meta.discourse.org',
            ).copyWith(user: _pollUser(id: 1, username: 'reader')),
          ]),
          api: api,
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        addTearDown(shell.dispose);
        addTearDown(() {
          if (!api.response.isCompleted) api.response.complete(freshUser);
        });

        await shell.load();
        await _waitFor(
          () => api.calls >= 1,
          description: 'the current-user request',
        );

        expect(shell.freshCurrentUserFor(_site), isNull);
        expect(_polls(shell).canCreatePollFor(_site), isFalse);
        expect(_polls(shell).freshCurrentUserFor(_site), isNull);

        api.response.complete(freshUser);
        await pumpEventQueue();

        expect(api.calls, 1);
        expect(shell.freshCurrentUserFor(_site)?.username, 'reader');
        expect(shell.freshCurrentUserFor(_site)?.staff, isTrue);
        expect(shell.freshCurrentUserFor(_site)?.groups, ['builders']);
        expect(_polls(shell).canCreatePollFor(_site), isTrue);
        expect(_polls(shell).freshCurrentUserFor(_site)?.groups, ['builders']);
      },
    );

    test('hydrates each site account once when selected', () async {
      final api = _PerSiteCurrentUserApi();
      final authenticator = FakeAuthenticator()
        ..keys[_site] = 'meta-key'
        ..keys[_site2] = 'community-key';
      final shell = ShellController(
        plugins: installedPlugins,
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(
            user: const DiscourseUser(id: 1, username: 'stored-reader'),
          ),
          instance('community.example.com').copyWith(
            user: const DiscourseUser(id: 2, username: 'stored-reader2'),
          ),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await _waitFor(
        () => api.calls.isNotEmpty,
        description: 'the initial site account hydration',
      );
      await pumpEventQueue();

      expect(api.calls, [_site]);
      expect(shell.freshCurrentUserFor(_site)?.username, 'reader');
      expect(shell.freshCurrentUserFor(_site)?.groups, ['meta-builders']);
      expect(shell.freshCurrentUserFor(_site2), isNull);
      expect(_polls(shell).canCreatePollFor(_site), isTrue);
      expect(_polls(shell).canCreatePollFor(_site2), isFalse);

      shell.selectInstance(1);
      await _waitFor(
        () => api.calls.length >= 2,
        description: 'the selected site account hydration',
      );
      await pumpEventQueue();

      expect(api.calls, [_site, _site2]);
      expect(shell.freshCurrentUserFor(_site2)?.groups, ['community-builders']);
      expect(_polls(shell).canCreatePollFor(_site2), isTrue);
      expect(_polls(shell).freshCurrentUserFor(_site2)?.groups, [
        'community-builders',
      ]);

      shell.selectInstance(0);
      await pumpEventQueue();

      expect(api.calls, [_site, _site2]);
    });
  });

  group('account changes during write admission', () {
    for (final scenario in [
      (action: 'like', optimistic: false),
      (action: 'reaction', optimistic: false),
      (action: 'poll', optimistic: false),
      (action: 'like', optimistic: true),
      (action: 'reaction', optimistic: true),
    ]) {
      final action = scenario.action;
      final stage = scenario.optimistic
          ? 'optimistic update'
          : 'write admission';
      test('$action stops after account replacement during $stage', () async {
        final poll = _poll();
        final api = _api(
          initial: _post(
            poll: poll,
            canLike: true,
            reactions: action == 'reaction'
                ? const Reactions(entries: [])
                : null,
          ),
          voteResponses: {
            FakeDiscourseApi.pollVoteKey(11, 'poll'): _answer(poll),
          },
        );
        final shell = (await _loadShell(api)).shell;
        addTearDown(shell.dispose);
        final post = shell.store.read<Post>(_site, 11)!;
        var replaced = false;
        shell.addListener(() {
          if (replaced || !shell.pluginPostWriteInFlight(_site, post.id)) {
            return;
          }
          if (scenario.optimistic) {
            final current = shell.store.read<Post>(_site, post.id)!;
            final applied = action == 'like'
                ? current.liked
                : current.reactions?.mine?.id == 'clap';
            if (!applied) return;
          }
          replaced = true;
          shell.lifecycle.invalidate(_site);
          shell.endPluginPostWrite(_site, post.id);
          shell.beginPluginPostWrite(_site, post.id);
        });

        switch (action) {
          case 'like':
            await shell.toggleLike(post, siteUrl: _site);
          case 'reaction':
            await _reactions(shell).toggle(post, 'clap', siteUrl: _site);
          case 'poll':
            await _castPollVote(shell, post, poll, ['b']);
        }

        expect(replaced, isTrue);
        expect(api.liked, isEmpty);
        expect(api.reacted, isEmpty);
        expect(api.pollVotes, isEmpty);
        expect(
          shell.pluginPostWriteInFlight(_site, post.id),
          isTrue,
          reason:
              'the obsolete operation must not release the new account write',
        );
      });
    }
  });

  group('successful poll writes', () {
    test('merge only the named personalized poll after voting', () async {
      final initialPoll = _poll();
      final untouched = _poll(name: 'second', voters: 4, firstVotes: 2);
      const reactions = Reactions(
        entries: [Reaction(id: 'clap', count: 3)],
        mine: Reaction(id: 'clap', canUndo: true),
        userCount: 3,
      );
      final answered = _poll(voters: 2, firstVotes: 1, selected: const ['b']);
      final key = FakeDiscourseApi.pollVoteKey(11, 'poll');
      final api = _api(
        initial: _post(
          poll: initialPoll,
          otherPoll: untouched,
          reactions: reactions,
        ),
        voteResponses: {key: _answer(answered)},
      );
      final (:shell, :tracker) = await _loadShell(api);
      addTearDown(shell.dispose);

      final result = await _castPollVote(
        shell,
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
        const ['b'],
      );

      expect(result.message, isNull);
      expect(result.reconciled, isFalse);
      expect(api.pollVotes, hasLength(1));
      expect(api.pollVotes.single.postId, 11);
      expect(api.pollVotes.single.pollName, 'poll');
      expect(api.pollVotes.single.options, ['b']);
      final stored = shell.store.read<Post>(_site, 11)!;
      expect(stored.polls?['poll'], answered);
      expect(stored.polls?['second'], untouched);
      expect(stored.reactions, reactions);
      expect(tracker.watchedChannels, contains('/polls/7'));
    });

    test('apply the personalized empty selection after removal', () async {
      final initialPoll = _poll(selected: const ['a']);
      final answered = _poll(voters: 0, firstVotes: 0, selected: const []);
      final key = FakeDiscourseApi.pollVoteKey(11, 'poll');
      final api = _api(
        initial: _post(poll: initialPoll),
        removalResponses: {key: _answer(answered)},
      );
      final (:shell, :tracker) = await _loadShell(api);
      addTearDown(shell.dispose);

      final result = await _removePollVote(
        shell,
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
      );

      expect(result.message, isNull);
      expect(result.reconciled, isFalse);
      expect(api.pollVotesRemoved, [(postId: 11, pollName: 'poll')]);
      expect(
        shell.store.read<Post>(_site, 11)?.polls?['poll']?.selection,
        PollSelection.none,
      );
    });
  });

  group('failed and uncertain poll writes', () {
    test(
      'preserve the saved selection and report a definite refusal',
      () async {
        final initialPoll = _poll(selected: const ['a']);
        final api = _api(
          initial: _post(poll: initialPoll),
          pollFailure: const WriteException(
            WriteFailure.validation,
            errors: ['This poll is closed.'],
          ),
        );
        final (:shell, :tracker) = await _loadShell(api);
        addTearDown(shell.dispose);

        final result = await _castPollVote(
          shell,
          shell.store.read<Post>(_site, 11)!,
          initialPoll,
          const ['b'],
        );

        expect(result.message, 'This poll is closed.');
        expect(result.reconciled, isFalse);
        expect(api.pollVotes.single.postId, 11);
        expect(api.pollVotes.single.pollName, 'poll');
        expect(api.pollVotes.single.options, ['b']);
        expect(
          shell.store.read<Post>(_site, 11)?.polls?['poll']?.selectedOptionIds,
          ['a'],
        );
        expect(api.postFetches, isEmpty);
      },
    );

    test(
      'refetch after an unreachable vote because the write may have landed',
      () async {
        final initialPoll = _poll(selected: const ['a']);
        final reconciled = _poll(
          voters: 2,
          firstVotes: 1,
          selected: const ['b'],
        );
        final api = _api(
          initial: _post(poll: initialPoll),
          pollFailure: const WriteException(WriteFailure.unreachable),
          postsById: {11: _post(poll: reconciled, cooked: '<p>Refetched</p>')},
        );
        final (:shell, :tracker) = await _loadShell(api);
        addTearDown(shell.dispose);

        final result = await _castPollVote(
          shell,
          shell.store.read<Post>(_site, 11)!,
          initialPoll,
          const ['b'],
        );

        expect(result.message, isNull);
        expect(result.reconciled, isTrue);
        expect(api.pollVotes.single.postId, 11);
        expect(api.pollVotes.single.pollName, 'poll');
        expect(api.pollVotes.single.options, ['b']);
        expect(api.postFetches, [
          [11],
        ]);
        expect(shell.store.read<Post>(_site, 11)?.cooked, '<p>Refetched</p>');
        expect(
          shell.store.read<Post>(_site, 11)?.polls?['poll']?.selectedOptionIds,
          ['b'],
        );
      },
    );
  });

  group('poll recovery admission', () {
    for (final remove in [false, true]) {
      final action = remove ? 'removal' : 'vote';
      for (final failure in [
        (
          name: 'unreachable',
          error: const WriteException(WriteFailure.unreachable),
        ),
        (name: 'unexpected', error: StateError('Poll response failed')),
      ]) {
        for (final change in [
          'disconnect',
          'account replacement',
          'shell disposal',
          'poll disposal',
          'no account change',
        ]) {
          test('${failure.name} $action recovery after $change', () async {
            final initialPoll = _poll();
            final initial = _post(poll: initialPoll);
            final reconciled = _post(
              poll: _poll(selected: remove ? const [] : const ['b']),
              cooked: '<p>Reconciled</p>',
            );
            final gate = Completer<void>();
            final api = _api(
              initial: initial,
              pollGate: gate,
              voteResponses: {
                FakeDiscourseApi.pollVoteKey(11, 'poll'): _answer(initialPoll),
              },
              removalResponses: {
                FakeDiscourseApi.pollVoteKey(11, 'poll'): _answer(initialPoll),
              },
              postsById: {11: reconciled},
            );
            final authenticator = FakeAuthenticator(
              credentials: const UserApiCredentials(
                key: 'replacement-key',
                apiVersion: 4,
                push: false,
              ),
            );
            final (:shell, tracker: _) = await _loadShell(
              api,
              authenticator: authenticator,
            );
            var disposed = false;
            addTearDown(() {
              if (!disposed) shell.dispose();
            });
            addTearDown(() {
              if (!gate.isCompleted) gate.complete();
            });
            final lease = shell.lifecycle.capture(_site);
            final writing = remove
                ? _removePollVote(shell, initial, initialPoll)
                : _castPollVote(shell, initial, initialPoll, const ['b']);
            await _waitFor(
              () => remove
                  ? api.pollVotesRemoved.isNotEmpty
                  : api.pollVotes.isNotEmpty,
              description: 'the admitted poll $action request',
            );
            expect(api.pollVotes, hasLength(remove ? 0 : 1));
            expect(api.pollVotesRemoved, hasLength(remove ? 1 : 0));
            expect(shell.pluginPostWriteInFlight(_site, 11), isTrue);
            expect(authenticator.keys[_site], 'api-key');

            switch (change) {
              case 'disconnect':
                expect(await shell.disconnectInstance(_site), isTrue);
                expect(shell.currentInstance?.isConnected, isFalse);
                expect(authenticator.disconnected, [_site]);
                expect(lease.isCurrent, isFalse);
              case 'account replacement':
                await shell.connectCurrentInstance();
                expect(shell.currentInstance?.isConnected, isTrue);
                expect(authenticator.keys[_site], 'replacement-key');
                expect(lease.isCurrent, isFalse);
              case 'shell disposal':
                shell.dispose();
                disposed = true;
                expect(lease.isCurrent, isFalse);
              case 'poll disposal':
                await shell.pluginSession.close();
                expect(lease.isCurrent, isTrue);
              case 'no account change':
                expect(lease.isCurrent, isTrue);
            }
            await pumpEventQueue();
            expect(api.postFetches, isEmpty);
            final held = shell.store.read<Post>(_site, 11);

            gate.completeError(failure.error);
            final result = await writing;
            await pumpEventQueue();

            expect(result.message, isNull);
            expect(result.reconciled, isTrue);
            if (change == 'no account change') {
              expect(api.postFetches, [
                [11],
              ]);
              expect(shell.store.read<Post>(_site, 11), same(reconciled));
              expect(shell.pluginPostWriteInFlight(_site, 11), isFalse);
            } else {
              expect(api.postFetches, isEmpty);
              expect(shell.store.read<Post>(_site, 11), same(held));
            }
          });
        }
      }
    }
  });

  group('shared post refresh admission', () {
    for (final change in ['disconnect', 'shell disposal']) {
      test('rejects a retained refresh after $change', () async {
        final api = _api(initial: _post(poll: _poll()));
        final (:shell, tracker: _) = await _loadShell(api);
        var disposed = false;
        addTearDown(() {
          if (!disposed) shell.dispose();
        });
        final lease = shell.lifecycle.capture(_site);
        if (change == 'disconnect') {
          expect(await shell.disconnectInstance(_site), isTrue);
        } else {
          shell.dispose();
          disposed = true;
        }
        expect(lease.isCurrent, isFalse);
        await pumpEventQueue();
        expect(api.postFetches, isEmpty);

        await shell.refreshPluginPost(_site, 7, 11, 'api-key', lease);

        expect(api.postFetches, isEmpty);
      });
    }
  });

  group('poll write ordering', () {
    for (final channel in ['/polls/7', '/topic/7/reactions']) {
      test(
        '$channel rejects invalid IDs without queuing a post refresh',
        () async {
          final gate = Completer<void>();
          final initialPoll = _poll();
          final answered = _poll(
            voters: 2,
            firstVotes: 1,
            selected: const ['b'],
          );
          final api = _api(
            initial: _post(poll: initialPoll),
            pollGate: gate,
            voteResponses: {
              FakeDiscourseApi.pollVoteKey(11, 'poll'): _answer(answered),
            },
            postsById: {11: _post(poll: answered, cooked: '<p>Live</p>')},
          );
          final (:shell, :tracker) = await _loadShell(api);
          addTearDown(shell.dispose);
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });

          final voting = _castPollVote(
            shell,
            shell.store.read<Post>(_site, 11)!,
            initialPoll,
            const ['b'],
          );
          await _waitFor(
            () => api.pollVotes.isNotEmpty,
            description: 'the poll vote request',
          );
          expect(shell.postWriteInFlight(11), isTrue);

          tracker.deliverTopicMessage(channel, jsonDecode('{"post_id":1e999}'));
          for (final id in <Object?>[
            double.infinity,
            double.negativeInfinity,
            double.nan,
            0,
            -1,
            11.75,
            9223372036854775808.0,
            '11',
          ]) {
            tracker.deliverTopicMessage(channel, {'post_id': id});
          }
          await pumpEventQueue();
          expect(api.postFetches, isEmpty);

          gate.complete();
          final result = await voting;
          expect(result.message, isNull);
          await pumpEventQueue();
          expect(api.postFetches, isEmpty);

          tracker.deliverTopicMessage(channel, const {'post_id': 11.0});
          await pumpEventQueue();
          expect(api.postFetches, [
            [11],
          ]);
          expect(shell.store.read<Post>(_site, 11)?.cooked, '<p>Live</p>');
        },
      );
    }

    test('queues and replays invalidations received during a write', () async {
      final gate = Completer<void>();
      final initialPoll = _poll();
      final answered = _poll(voters: 2, firstVotes: 1, selected: const ['b']);
      final live = _poll(voters: 9, firstVotes: 5, selected: const ['b']);
      final key = FakeDiscourseApi.pollVoteKey(11, 'poll');
      final api = _api(
        initial: _post(poll: initialPoll),
        pollGate: gate,
        voteResponses: {key: _answer(answered)},
        postsById: {11: _post(poll: live, cooked: '<p>Live</p>')},
      );
      final (:shell, :tracker) = await _loadShell(api);
      addTearDown(shell.dispose);
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      final voting = _castPollVote(
        shell,
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
        const ['b'],
      );
      await _waitFor(
        () => api.pollVotes.isNotEmpty,
        description: 'the poll vote request',
      );
      expect(api.pollVotes, hasLength(1));
      expect(api.pollVotes.single.postId, 11);
      expect(api.pollVotes.single.pollName, 'poll');
      expect(api.pollVotes.single.options, ['b']);
      expect(shell.postWriteInFlight(11), isTrue);

      tracker.deliverTopicMessage('/polls/7', const {'post_id': 11});
      await pumpEventQueue();
      expect(api.postFetches, isEmpty);

      gate.complete();
      final result = await voting;
      expect(result.message, isNull);
      expect(result.reconciled, isFalse);
      await pumpEventQueue();

      expect(api.postFetches, [
        [11],
      ]);
      expect(shell.store.read<Post>(_site, 11)?.cooked, '<p>Live</p>');
      expect(shell.store.read<Post>(_site, 11)?.polls?['poll']?.voters, 9);
    });

    test(
      'reconciles a competing action without issuing a second write',
      () async {
        final gate = Completer<void>();
        final initialPoll = _poll();
        final answered = _poll(voters: 2, firstVotes: 1, selected: const ['b']);
        final key = FakeDiscourseApi.pollVoteKey(11, 'poll');
        final api = _api(
          initial: _post(poll: initialPoll),
          pollGate: gate,
          voteResponses: {key: _answer(answered)},
        );
        final (:shell, tracker: _) = await _loadShell(api);
        addTearDown(shell.dispose);
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });

        final voting = _castPollVote(
          shell,
          shell.store.read<Post>(_site, 11)!,
          initialPoll,
          const ['b'],
        );
        await _waitFor(
          () => api.pollVotes.isNotEmpty,
          description: 'the active poll vote request',
        );

        final competing = await _removePollVote(
          shell,
          shell.store.read<Post>(_site, 11)!,
          initialPoll,
        );

        expect(competing.message, isNull);
        expect(competing.reconciled, isTrue);
        expect(api.pollVotes, hasLength(1));
        expect(api.pollVotesRemoved, isEmpty);

        gate.complete();
        final result = await voting;
        expect(result.message, isNull);
        expect(result.reconciled, isFalse);
        expect(shell.store.read<Post>(_site, 11)?.polls?['poll'], answered);
      },
    );

    test(
      'supersedes a pre-write refresh and replays it after the write',
      () async {
        final postGate = Completer<void>();
        final initialPoll = _poll();
        final answered = _poll(voters: 2, firstVotes: 1, selected: const ['b']);
        final live = _poll(voters: 6, firstVotes: 3, selected: const ['b']);
        final key = FakeDiscourseApi.pollVoteKey(11, 'poll');
        final api = _api(
          initial: _post(poll: initialPoll),
          voteResponses: {key: _answer(answered)},
          postsById: {11: _post(poll: live, cooked: '<p>Live replay</p>')},
          postGate: postGate,
        );
        final (:shell, :tracker) = await _loadShell(api);
        addTearDown(shell.dispose);
        addTearDown(() {
          if (!postGate.isCompleted) postGate.complete();
        });

        tracker.deliverTopicMessage('/polls/7', const {'post_id': 11});
        await _waitFor(
          () => api.postFetches.isNotEmpty,
          description: 'the pre-write post refresh',
        );

        await _castPollVote(
          shell,
          shell.store.read<Post>(_site, 11)!,
          initialPoll,
          const ['b'],
        );
        await _waitFor(
          () => api.postFetches.length >= 2,
          description: 'the queued post-write refresh',
        );

        // The write invalidates the first read and queues a replay behind it.
        expect(api.postFetches, [
          [11],
          [11],
        ]);
        postGate.complete();
        await pumpEventQueue();

        expect(shell.store.read<Post>(_site, 11)?.cooked, '<p>Live replay</p>');
        expect(shell.store.read<Post>(_site, 11)?.polls?['poll']?.voters, 6);
      },
    );
  });

  group('vote admission', () {
    test(
      'rejects an archived topic without calling the plugin route',
      () async {
        final initialPoll = _poll();
        final api = _api(initial: _post(poll: initialPoll));
        final (:shell, :tracker) = await _loadShell(api);
        addTearDown(shell.dispose);
        shell.store.update<TopicDetail>(
          _site,
          7,
          (detail) => detail.copyWith(archived: true),
        );

        final result = await _castPollVote(
          shell,
          shell.store.read<Post>(_site, 11)!,
          initialPoll,
          const ['b'],
        );

        expect(result.message, 'Voting is unavailable in archived topics.');
        expect(result.reconciled, isFalse);
        expect(api.pollVotes, isEmpty);
      },
    );
  });

  group('cross-plugin state isolation', () {
    test(
      'restores only reaction state while preserving a concurrent poll refresh',
      () async {
        final gate = Completer<void>();
        final initialPoll = _poll(voters: 1);
        final refreshedPoll = _poll(voters: 7, firstVotes: 4);
        const reactions = Reactions(
          entries: [Reaction(id: 'clap', count: 1)],
          mine: Reaction(id: 'clap', canUndo: true),
          userCount: 1,
        );
        final api = _api(
          initial: _post(poll: initialPoll, reactions: reactions),
          reactionGate: gate,
          reactionFailure: const WriteException(
            WriteFailure.validation,
            errors: ['Reaction refused.'],
          ),
        );
        final (:shell, :tracker) = await _loadShell(api);
        addTearDown(shell.dispose);
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final post = shell.store.read<Post>(_site, 11)!;

        final reacting = _reactions(shell).toggle(post, 'clap', siteUrl: _site);
        await _waitFor(
          () => api.reacted.isNotEmpty,
          description: 'the reaction request',
        );
        expect(api.reacted, [(postId: 11, reaction: 'clap')]);
        shell.store.update<Post>(
          _site,
          11,
          (held) => held.withPlugins(
            held.plugins.withValue(
              pollsDataKey,
              Polls(byName: {'poll': refreshedPoll}),
            ),
          ),
        );

        gate.complete();
        expect(await reacting, 'Reaction refused.');

        final stored = shell.store.read<Post>(_site, 11)!;
        expect(stored.reactions, reactions);
        expect(stored.polls?['poll'], refreshedPoll);
      },
    );
  });
}
