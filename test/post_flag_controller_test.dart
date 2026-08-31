import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

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

const _siteUrl = 'https://meta.discourse.org';
const _offTopic = PostFlagType(
  id: 3,
  nameKey: 'off_topic',
  name: 'Off-Topic',
  description: '<p>Not relevant to the discussion.</p>',
  appliesTo: ['Post'],
  system: true,
);
const _notifyUser = PostFlagType(
  id: 7,
  nameKey: 'notify_user',
  name: 'Send @%{username} a message',
  description: '<p>Help this person improve their post.</p>',
  requireMessage: true,
  appliesTo: ['Post'],
  system: true,
);
const _disabled = PostFlagType(
  id: 91,
  nameKey: 'custom_disabled',
  name: 'Old reason',
  description: '',
  enabled: false,
  appliesTo: ['Post'],
);
const _topicOnly = PostFlagType(
  id: 92,
  nameKey: 'topic_reason',
  name: 'Topic reason',
  description: '',
  appliesTo: ['Topic'],
);
const _catalog = SitePostActionCatalog(
  postFlags: [_offTopic, _notifyUser, _disabled, _topicOnly],
  topicFlags: [_topicOnly],
);

Post _post({
  bool hidden = false,
  bool userDeleted = false,
  bool canLike = true,
  List<PostActionSummary> actions = const [
    PostActionSummary(id: 3, canAct: true),
    PostActionSummary(id: 7, canAct: true),
  ],
}) => Post(
  id: 42,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Hello</p>',
  hidden: hidden,
  userDeleted: userDeleted,
  canLike: canLike,
  postActions: actions,
);

Post _actedPost() => _post(
  actions: const [
    PostActionSummary(id: 3, acted: true),
    PostActionSummary(id: 7, canAct: false),
  ],
);

Future<({ShellController shell, FakeDiscourseApi api})> _shell({
  Completer<void>? flagGate,
  WriteException? flagFailure,
  Post? flagResponse,
}) async {
  final api = FakeDiscourseApi(
    feeds: const {'/latest.json': []},
    categoryPostActionCatalog: _catalog,
    siteConfigs: const {_siteUrl: SiteConfig(minPersonalMessagePostLength: 10)},
    flagGate: flagGate,
    flagFailure: flagFailure,
    flagResponses: {42: ?flagResponse},
  );
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(
        user: const DiscourseUser(id: 1, username: 'reader'),
        config: const SiteConfig(minPersonalMessagePostLength: 10),
      ),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  for (
    var attempt = 0;
    attempt < 20 && shell.postFlagTypesFor(_siteUrl).isEmpty;
    attempt++
  ) {
    await pumpEventQueue();
  }
  expect(shell.postFlagTypesFor(_siteUrl), _catalog.postFlags);
  shell.store.put(_siteUrl, _post());
  shell.store.put(
    _siteUrl,
    const TopicDetail(
      id: 7,
      title: 'A topic',
      stream: [42],
      canFlagTopic: true,
      topicActions: [PostActionSummary(id: 92, canAct: true)],
    ),
  );
  return (shell: shell, api: api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'availability intersects catalog and post permissions in web order',
    () async {
      final (:shell, :api) = await _shell();
      addTearDown(shell.dispose);
      final post = shell.store.read<Post>(_siteUrl, 42)!;

      expect(
        shell.availablePostFlagTypes(_siteUrl, post).map((type) => type.id),
        [7, 3],
      );
      expect(api.categoryRequests, [_siteUrl]);
    },
  );

  test('successful flagging stores only the authoritative response', () async {
    final (:shell, :api) = await _shell(flagResponse: _actedPost());
    addTearDown(shell.dispose);
    final post = shell.store.read<Post>(_siteUrl, 42)!;

    expect(await shell.createPostFlag(_siteUrl, post, _offTopic), isNull);

    expect(api.flagsCreated, [
      (postId: 42, postActionTypeId: 3, message: null),
    ]);
    final held = shell.store.read<Post>(_siteUrl, 42)!;
    expect(held.actedFlagSummaries.single.id, 3);
    expect(shell.availablePostFlagTypes(_siteUrl, held), isEmpty);
    expect(shell.postWriteInFlight(42, siteUrl: _siteUrl), isFalse);
  });

  test(
    'topic flagging intersects its own catalog and action summary',
    () async {
      final (:shell, :api) = await _shell();
      addTearDown(shell.dispose);
      final topic = shell.store.read<TopicDetail>(_siteUrl, 7)!;

      expect(shell.availableTopicFlagTypes(_siteUrl, topic), [_topicOnly]);
      expect(await shell.createTopicFlag(_siteUrl, topic, _topicOnly), isNull);

      expect(api.topicFlagsCreated, [
        (topicId: 7, postActionTypeId: 92, message: null),
      ]);
      final held = shell.store.read<TopicDetail>(_siteUrl, 7)!;
      expect(shell.availableTopicFlagTypes(_siteUrl, held), isEmpty);
      expect(held.topicActions.single.acted, isTrue);
      expect(shell.topicFlagWriteInFlight(_siteUrl, 7), isFalse);
    },
  );

  test('required explanations are validated and forwarded unchanged', () async {
    final (:shell, :api) = await _shell(flagResponse: _actedPost());
    addTearDown(shell.dispose);
    final post = shell.store.read<Post>(_siteUrl, 42)!;

    expect(
      await shell.createPostFlag(
        _siteUrl,
        post,
        _notifyUser,
        message: 'too short',
      ),
      'Your message must be between 10 and 500 characters.',
    );
    expect(api.flagsCreated, isEmpty);

    expect(
      await shell.createPostFlag(
        _siteUrl,
        post,
        _notifyUser,
        message: List.filled(501, 'x').join(),
      ),
      'Your message must be between 10 and 500 characters.',
    );
    expect(api.flagsCreated, isEmpty);

    const message = 'Please consider rephrasing this sentence.';
    expect(
      await shell.createPostFlag(_siteUrl, post, _notifyUser, message: message),
      isNull,
    );
    expect(api.flagsCreated.single.message, message);
  });

  test('stale or unauthorized choices never send a request', () async {
    final (:shell, :api) = await _shell();
    addTearDown(shell.dispose);

    final cases = <(Post, PostFlagType)>[
      (
        _post(actions: const [PostActionSummary(id: 91, canAct: true)]),
        _disabled,
      ),
      (
        _post(actions: const [PostActionSummary(id: 92, canAct: true)]),
        _topicOnly,
      ),
      (_post(actions: const []), _offTopic),
      (
        _post(actions: const [PostActionSummary(id: 3, acted: true)]),
        _offTopic,
      ),
      (
        _post(
          actions: const [
            PostActionSummary(id: 7, acted: true),
            PostActionSummary(id: 3, canAct: true),
          ],
        ),
        _offTopic,
      ),
      (_post(hidden: true), _offTopic),
      (_post(userDeleted: true), _offTopic),
    ];

    for (final (post, type) in cases) {
      shell.store.put(_siteUrl, post);
      expect(
        await shell.createPostFlag(_siteUrl, post, type),
        'This post can no longer be flagged.',
      );
    }
    expect(
      await shell.createPostFlag(
        _siteUrl,
        _post(),
        const PostFlagType(
          id: 404,
          nameKey: 'removed',
          name: 'Removed',
          description: '',
          appliesTo: ['Post'],
        ),
      ),
      'This post can no longer be flagged.',
    );
    expect(api.flagsCreated, isEmpty);
  });

  test('the shared post guard prevents a flag racing another action', () async {
    final gate = Completer<void>();
    final (:shell, :api) = await _shell(
      flagGate: gate,
      flagResponse: _actedPost(),
    );
    addTearDown(shell.dispose);
    final post = shell.store.read<Post>(_siteUrl, 42)!;

    final flagging = shell.createPostFlag(_siteUrl, post, _offTopic);
    await _waitFor(
      () => api.flagsCreated.isNotEmpty,
      description: 'the post flag request',
    );
    expect(api.flagsCreated, [
      (postId: 42, postActionTypeId: 3, message: null),
    ]);
    expect(shell.postWriteInFlight(42, siteUrl: _siteUrl), isTrue);

    expect(await shell.toggleLike(post, siteUrl: _siteUrl), isNull);
    expect(api.liked, isEmpty);

    gate.complete();
    expect(await flagging, isNull);
    expect(shell.postWriteInFlight(42, siteUrl: _siteUrl), isFalse);
  });

  test(
    'a server refusal preserves held state and releases the guard',
    () async {
      final (:shell, :api) = await _shell(
        flagFailure: const WriteException(
          WriteFailure.validation,
          errors: ['That flag is not available.'],
        ),
      );
      addTearDown(shell.dispose);
      final post = shell.store.read<Post>(_siteUrl, 42)!;

      expect(
        await shell.createPostFlag(_siteUrl, post, _offTopic),
        'That flag is not available.',
      );
      expect(shell.store.read<Post>(_siteUrl, 42), same(post));
      expect(shell.postWriteInFlight(42, siteUrl: _siteUrl), isFalse);
      expect(api.flagsCreated, hasLength(1));
    },
  );
}
