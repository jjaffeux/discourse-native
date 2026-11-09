import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/plugin_data.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _topicId = 7;
const _authorId = 9;
const _readerId = 1;
const _otherId = 44;
const _likeTypeId = 2;

/// Five held posts behind the real HTTP reader, answering as
/// `TopicViewSerializer`, `TopicViewPostsSerializer` and `PostSerializer` do.
final class _Forum extends FakeDiscourseApi {
  _Forum({required DiscourseUser user})
    : super(
        user: user,
        feeds: const {
          '/latest.json': [Topic(id: _topicId, title: 'A topic', slug: 'a')],
        },
      );

  final likes = <int, int>{for (var id = 1; id <= 5; id++) id: 3};
  final likedByReader = <int>{};
  final postReads = <List<int>>[];
  int postReadBytes = 0;
  Completer<void>? holdLike;
  Completer<void>? holdTopic;
  Completer<void>? holdPosts;

  late final _reader = DiscourseApi(client: MockClient(_answer));

  Future<http.Response> _answer(http.Request request) async {
    final path = request.url.path;
    if (path == '/t/$_topicId.json') {
      // The body is what the server knew when it answered the request.
      final hold = holdTopic;
      final response = _topicResponse();
      await hold?.future;
      return response;
    }
    if (path == '/t/$_topicId/posts.json') {
      final ids = [
        for (final value in request.url.queryParametersAll['post_ids[]']!)
          int.parse(value),
      ];
      postReads.add(ids);
      final hold = holdPosts;
      final response = _json({
        'post_stream': {
          'posts': [for (final id in ids) _postJson(id)],
        },
        'id': _topicId,
      });
      await hold?.future;
      postReadBytes += response.bodyBytes.length;
      return response;
    }
    if (path == '/post_actions.json' && request.method == 'POST') {
      final id = (jsonDecode(request.body) as Map)['id'] as int;
      await holdLike?.future;
      likes[id] = likes[id]! + 1;
      likedByReader.add(id);
      return _json(_postJson(id));
    }
    throw StateError('Unexpected request: ${request.method} $path');
  }

  http.Response _topicResponse() => _json({
    'post_stream': {
      'posts': [for (var id = 1; id <= 5; id++) _postJson(id)],
      'stream': [1, 2, 3, 4, 5],
    },
    'id': _topicId,
    'title': 'A topic',
    'fancy_title': 'A topic',
    'slug': 'a',
    'posts_count': 5,
    'highest_post_number': 5,
    'last_posted_at': '2026-09-01T10:00:00.000Z',
    'message_bus_last_id': 100,
    'closed': false,
    'archived': false,
    'visible': true,
    'details': {'can_create_post': true, 'notification_level': 1},
  });

  http.Response _json(Map<String, Object?> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, Object?> _postJson(int id) => {
    'id': id,
    'name': 'Sam',
    'username': 'sam',
    'avatar_template': '/user_avatar/meta.discourse.org/sam/{size}/1_2.png',
    'created_at': '2026-09-01T10:00:00.000Z',
    'cooked': '<p>${'A paragraph of an ordinary reply. ' * 20}</p>',
    'post_number': id,
    'post_type': 1,
    'updated_at': '2026-09-01T10:00:00.000Z',
    'reply_count': 0,
    'reply_to_post_number': null,
    'quote_count': 0,
    'incoming_link_count': 0,
    'reads': 12,
    'readers_count': 11,
    'score': 4.2,
    'yours': false,
    'topic_id': _topicId,
    'topic_slug': 'a',
    'display_username': 'Sam',
    'primary_group_name': null,
    'flair_name': null,
    'version': 1,
    'can_edit': false,
    'can_delete': false,
    'can_recover': false,
    'can_see_hidden_post': false,
    'can_wiki': false,
    'read': true,
    'user_title': null,
    'bookmarked': false,
    'actions_summary': [
      {
        'id': _likeTypeId,
        'count': likes[id],
        if (likedByReader.contains(id)) ...{'acted': true, 'can_undo': true},
        if (!likedByReader.contains(id)) 'can_act': true,
      },
    ],
    'moderator': false,
    'admin': false,
    'staff': false,
    'user_id': _authorId,
    'hidden': false,
    'trust_level': 1,
    'deleted_at': null,
    'user_deleted': false,
    'edit_reason': null,
    'can_view_edit_history': true,
    'wiki': false,
    'reviewable_id': null,
    'reviewable_score_count': 0,
    'reviewable_score_pending_count': 0,
    'post_url': '/t/a/$_topicId/$id',
  };

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
  }) => _reader.topic(
    siteUrl: siteUrl,
    slug: slug,
    id: id,
    postNumber: postNumber,
    summary: summary,
    apiKey: apiKey,
    clientId: clientId,
    abortTrigger: abortTrigger,
  );

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) => _reader.posts(
    siteUrl: siteUrl,
    topicId: topicId,
    ids: ids,
    includeRaw: includeRaw,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) => _reader.likePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );
}

/// `PostActionCreator#notify_subscribers` through
/// `Post#publish_change_to_clients!`, where `user_id` names who acted.
Map<String, Object?> _like(
  int id, {
  required int count,
  required int actor,
  String type = 'liked',
}) => {
  'id': id,
  'post_number': id,
  'updated_at': '2026-09-01T10:01:00.000Z',
  'user_id': actor,
  'last_editor_id': _authorId,
  'type': type,
  'version': 1,
  'likes_count': count,
};

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

Future<({ShellController shell, _Forum forum, FakeSiteTracker tracker})> _open({
  DiscourseUser user = const DiscourseUser(id: _readerId, username: 'reader'),
  InstalledPlugins? plugins,
}) async {
  final forum = _Forum(user: user);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org', user: user),
    ]),
    api: forum,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: plugins ?? installedPlugins,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  shell.pushContent(
    ContentRoute.topic(topicId: _topicId, slug: 'a', title: 'A topic'),
  );
  await shell.loadTopic(_topicId, 'a');
  await _settle();
  return (shell: shell, forum: forum, tracker: FakeSiteTracker.built.single);
}

Post _held(ShellController shell, int id) =>
    shell.store.read<Post>(_siteUrl, id)!;

void _report(String shape, _Forum forum) {
  // ignore: avoid_print
  print('PERF_PROOF live-like ${shape}_post_reads=${forum.postReads.length}');
  // ignore: avoid_print
  print('PERF_PROOF live-like ${shape}_post_read_bytes=${forum.postReadBytes}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ten likes from other readers read no post', () async {
    final (:shell, :forum, :tracker) = await _open();

    for (var count = 4; count <= 13; count++) {
      tracker.deliverTopicMessage(
        '/topic/$_topicId',
        _like(2, count: count, actor: _otherId),
      );
      await _settle();
    }

    _report('others', forum);
    expect(forum.postReads, isEmpty);
    expect(forum.postReadBytes, 0);
    final post = _held(shell, 2);
    expect(post.likeCount, 13);
    expect(post.liked, isFalse);
    expect(post.canLike, isTrue);
    expect(_held(shell, 1).likeCount, 3);
  });

  test('another reader taking a like back lowers the count', () async {
    final (:shell, :forum, :tracker) = await _open();

    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(2, count: 2, actor: _otherId, type: 'unliked'),
    );
    await _settle();

    expect(forum.postReads, isEmpty);
    expect(_held(shell, 2).likeCount, 2);
    expect(_held(shell, 2).liked, isFalse);
  });

  test('the echo of the reader\'s own like reads no post', () async {
    final (:shell, :forum, :tracker) = await _open();

    final hold = forum.holdLike = Completer<void>();
    final write = shell.toggleLike(_held(shell, 3));
    await pumpEventQueue();
    expect(_held(shell, 3).likeCount, 4);

    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(3, count: 4, actor: _readerId),
    );
    await pumpEventQueue();
    hold.complete();
    expect(await write, isNull);
    await _settle();

    _report('own_echo_during_write', forum);
    expect(forum.postReads, isEmpty);
    final post = _held(shell, 3);
    expect(post.likeCount, 4);
    expect(post.liked, isTrue);
    expect(post.canUnlike, isTrue);
  });

  test('the echo arriving after the write reads no post', () async {
    final (:shell, :forum, :tracker) = await _open();

    expect(await shell.toggleLike(_held(shell, 3)), isNull);
    await _settle();
    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(3, count: 4, actor: _readerId),
    );
    await _settle();

    _report('own_echo_after_write', forum);
    expect(forum.postReads, isEmpty);
    final post = _held(shell, 3);
    expect(post.likeCount, 4);
    expect(post.liked, isTrue);
    expect(post.canUnlike, isTrue);
  });

  test('the reader\'s like from another device turns the button on', () async {
    final (:shell, :forum, :tracker) = await _open();

    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(2, count: 4, actor: _readerId),
    );
    await _settle();

    expect(forum.postReads, isEmpty);
    final post = _held(shell, 2);
    expect(post.likeCount, 4);
    expect(post.liked, isTrue);
    expect(post.canLike, isFalse);
    expect(post.canUnlike, isTrue);
  });

  test('the serializer hides ignored likes, so such a viewer reads', () async {
    final (:shell, :forum, :tracker) = await _open(
      user: DiscourseUser(
        id: _readerId,
        username: 'reader',
        plugins: PluginData.none.withValue(
          chatCurrentUserDataKey,
          const ChatCurrentUser(ignoredUsernames: ['someone']),
        ),
      ),
    );

    forum.likes[2] = 3;
    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(2, count: 4, actor: _otherId),
    );
    await _settle();

    expect(forum.postReads, [
      [2],
    ]);
    expect(_held(shell, 2).likeCount, 3);
  });

  test('a message with no count still reads the post', () async {
    final (:shell, :forum, :tracker) = await _open();

    forum.likes[2] = 8;
    tracker.deliverTopicMessage('/topic/$_topicId', const {
      'type': 'liked',
      'id': 2,
    });
    await _settle();

    expect(forum.postReads, [
      [2],
    ]);
    expect(_held(shell, 2).likeCount, 8);
  });

  test('a like on a post this reader does not hold reads nothing', () async {
    final (:shell, :forum, :tracker) = await _open();

    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(99, count: 4, actor: _otherId),
    );
    await _settle();

    expect(forum.postReads, isEmpty);
    expect(shell.store.read<Post>(_siteUrl, 99), isNull);
  });

  test('a topic read sent before a like cannot lower its count', () async {
    final (:shell, :forum, :tracker) = await _open();

    final hold = forum.holdTopic = Completer<void>();
    final read = shell.loadTopic(_topicId, 'a', force: true);
    await pumpEventQueue();
    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(2, count: 4, actor: _otherId),
    );
    expect(_held(shell, 2).likeCount, 4);
    hold.complete();
    await read;
    await _settle();

    expect(forum.postReads, isEmpty);
    expect(_held(shell, 2).likeCount, 4);

    forum.holdTopic = null;
    forum.likes[2] = 9;
    await shell.loadTopic(_topicId, 'a', force: true);
    await _settle();

    expect(_held(shell, 2).likeCount, 9);
  });

  test('a like during a read of the post reads it again', () async {
    final (:shell, :forum, :tracker) = await _open();

    final hold = forum.holdPosts = Completer<void>();
    tracker.deliverTopicMessage('/topic/$_topicId', const {
      'type': 'revised',
      'id': 2,
    });
    await _settle();
    expect(forum.postReads, hasLength(1));

    forum.likes[2] = 4;
    forum.holdPosts = null;
    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(2, count: 4, actor: _otherId),
    );
    hold.complete();
    await _settle();

    expect(forum.postReads, hasLength(2));
    expect(_held(shell, 2).likeCount, 4);
  });

  test('another reader\'s like during a write reads after it', () async {
    final (:shell, :forum, :tracker) = await _open();

    final hold = forum.holdLike = Completer<void>();
    final write = shell.toggleLike(_held(shell, 3));
    await pumpEventQueue();
    forum.likes[3] = 4;
    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _like(3, count: 4, actor: _otherId),
    );
    await pumpEventQueue();
    hold.complete();
    expect(await write, isNull);
    await _settle();

    expect(forum.postReads, [
      [3],
    ]);
    expect(_held(shell, 3).likeCount, 5);
    expect(_held(shell, 3).liked, isTrue);
  });
}
