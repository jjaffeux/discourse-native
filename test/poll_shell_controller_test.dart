import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _site2 = 'https://community.example.com';

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
    return DiscourseUser(
      id: siteUrl == _site ? 1 : 2,
      username: siteUrl == _site ? 'reader' : 'reader2',
      canCreatePoll: true,
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
}) {
  var plugins = PluginData.none;
  if (poll != null) {
    final polls = {poll.name: poll};
    if (otherPoll != null) polls[otherPoll.name] = otherPoll;
    plugins = plugins.withValue<Polls>(Polls(byName: Map.unmodifiable(polls)));
  }
  if (reactions != null) {
    plugins = plugins.withValue<Reactions>(reactions);
  }
  return Post(
    id: 11,
    postNumber: 2,
    username: 'sam',
    cooked: cooked,
    canLike: reactions != null,
    plugins: plugins,
  );
}

Future<({ShellController shell, FakeSiteTracker tracker})> _loadShell(
  FakeDiscourseApi api,
) async {
  final authenticator = FakeAuthenticator();
  authenticator.keys[_site] = 'api-key';
  final shell = ShellController(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a persisted poll capability stays unauthorized until this session refreshes it',
    () async {
      final api = _GatedCurrentUserApi();
      final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(
            user: const DiscourseUser(
              id: 1,
              username: 'reader',
              canCreatePoll: true,
            ),
          ),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      while (api.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(shell.canCreatePollFor(_site), isFalse);
      expect(shell.freshCurrentUserFor(_site), isNull);

      api.response.complete(
        const DiscourseUser(
          id: 1,
          username: 'reader',
          canCreatePoll: true,
          staff: true,
          groups: ['builders'],
        ),
      );
      await pumpEventQueue();

      expect(api.calls, 1);
      expect(shell.canCreatePollFor(_site), isTrue);
      expect(shell.freshCurrentUserFor(_site)?.groups, ['builders']);
    },
  );

  test(
    'session poll capabilities refresh once for every connected site',
    () async {
      final api = _PerSiteCurrentUserApi();
      final authenticator = FakeAuthenticator()
        ..keys[_site] = 'meta-key'
        ..keys[_site2] = 'community-key';
      final shell = ShellController(
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
      while (api.calls.length < 2) {
        await pumpEventQueue();
      }
      await pumpEventQueue();

      expect(api.calls.where((site) => site == _site), hasLength(1));
      expect(api.calls.where((site) => site == _site2), hasLength(1));
      expect(shell.canCreatePollFor(_site), isTrue);
      expect(shell.canCreatePollFor(_site2), isTrue);
      expect(shell.freshCurrentUserFor(_site2)?.groups, ['community-builders']);
    },
  );

  test('a successful vote merges only the named personalized poll', () async {
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

    final result = await shell.castPollVote(
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

  test('vote removal applies the personalized empty selection', () async {
    final initialPoll = _poll(selected: const ['a']);
    final answered = _poll(voters: 0, firstVotes: 0, selected: const []);
    final key = FakeDiscourseApi.pollVoteKey(11, 'poll');
    final api = _api(
      initial: _post(poll: initialPoll),
      removalResponses: {key: _answer(answered)},
    );
    final (:shell, :tracker) = await _loadShell(api);
    addTearDown(shell.dispose);

    final result = await shell.removePollVote(
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

  test(
    'a definite refusal preserves saved selection and reports the server message',
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

      final result = await shell.castPollVote(
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
        const ['b'],
      );

      expect(result.message, 'This poll is closed.');
      expect(result.reconciled, isFalse);
      expect(
        shell.store.read<Post>(_site, 11)?.polls?['poll']?.selectedOptionIds,
        ['a'],
      );
      expect(api.postFetches, isEmpty);
    },
  );

  test(
    'an unreachable vote refetches because the idempotent write may have landed',
    () async {
      final initialPoll = _poll(selected: const ['a']);
      final reconciled = _poll(voters: 2, firstVotes: 1, selected: const ['b']);
      final api = _api(
        initial: _post(poll: initialPoll),
        pollFailure: const WriteException(WriteFailure.unreachable),
        postsById: {11: _post(poll: reconciled, cooked: '<p>Refetched</p>')},
      );
      final (:shell, :tracker) = await _loadShell(api);
      addTearDown(shell.dispose);

      final result = await shell.castPollVote(
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
        const ['b'],
      );

      expect(result.message, isNull);
      expect(result.reconciled, isTrue);
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

  test(
    'poll invalidations received during a write are queued and replayed',
    () async {
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

      final voting = shell.castPollVote(
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
        const ['b'],
      );
      while (api.pollVotes.isEmpty) {
        await pumpEventQueue();
      }
      expect(shell.postWriteInFlight(11), isTrue);

      tracker.deliverTopicMessage('/polls/7', const {'post_id': 11});
      await pumpEventQueue();
      expect(api.postFetches, isEmpty);

      // A second action on the same post is serialized behind the active one.
      final serialized = await shell.removePollVote(
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
      );
      expect(serialized.message, isNull);
      expect(serialized.reconciled, isTrue);
      expect(api.pollVotesRemoved, isEmpty);

      gate.complete();
      expect((await voting).message, isNull);
      await pumpEventQueue();

      expect(api.postFetches, [
        [11],
      ]);
      expect(shell.store.read<Post>(_site, 11)?.cooked, '<p>Live</p>');
      expect(shell.store.read<Post>(_site, 11)?.polls?['poll']?.voters, 9);
    },
  );

  test(
    'a pre-write poll refresh is superseded and replayed after the write',
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

      tracker.deliverTopicMessage('/polls/7', const {'post_id': 11});
      while (api.postFetches.isEmpty) {
        await pumpEventQueue();
      }

      await shell.castPollVote(
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
        const ['b'],
      );
      while (api.postFetches.length < 2) {
        await pumpEventQueue();
      }

      // The first read was invalidated by the write; the second is its queued
      // post-write replay and is allowed to land once the shared gate opens.
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

  test(
    'an archived topic refuses a vote without calling the plugin route',
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

      final result = await shell.castPollVote(
        shell.store.read<Post>(_site, 11)!,
        initialPoll,
        const ['b'],
      );

      expect(result.message, 'Voting is unavailable in archived topics.');
      expect(api.pollVotes, isEmpty);
    },
  );

  test(
    'reaction rollback restores only Reactions and keeps a concurrent poll refresh',
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
      final post = shell.store.read<Post>(_site, 11)!;

      final reacting = shell.toggleReaction(post, 'clap');
      while (api.reacted.isEmpty) {
        await pumpEventQueue();
      }
      shell.store.update<Post>(
        _site,
        11,
        (held) => held.withPlugins(
          held.plugins.withValue<Polls>(Polls(byName: {'poll': refreshedPoll})),
        ),
      );

      gate.complete();
      expect(await reacting, 'Reaction refused.');

      final stored = shell.store.read<Post>(_site, 11)!;
      expect(stored.reactions, reactions);
      expect(stored.polls?['poll'], refreshedPoll);
    },
  );
}
