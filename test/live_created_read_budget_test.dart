import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _topicId = 7;
const _authorId = 9;

/// One topic behind the real HTTP reader, answering as `TopicViewSerializer`
/// does for `/t/{id}.json` and `TopicViewPostsSerializer` for
/// `/t/{id}/posts.json`.
final class _Forum extends FakeDiscourseApi {
  _Forum(int posts)
    : super(
        user: const DiscourseUser(id: 1, username: 'reader'),
        feeds: const {
          '/latest.json': [Topic(id: _topicId, title: 'A topic', slug: 'a')],
        },
      ) {
    stream.addAll([for (var id = 1; id <= posts; id++) id]);
  }

  final stream = <int>[];
  final postReads = <List<int>>[];
  int fullReads = 0;

  late final _reader = DiscourseApi(client: MockClient(_answer));

  Future<http.Response> _answer(http.Request request) async {
    final path = request.url.path;
    if (path == '/t/$_topicId.json') {
      fullReads++;
      return _json({
        'post_stream': {
          'posts': [for (final id in stream.take(20)) _postJson(id)],
          'stream': stream,
        },
        'id': _topicId,
        'title': 'A topic',
        'fancy_title': 'A topic',
        'slug': 'a',
        'posts_count': stream.length,
        'highest_post_number': stream.last,
        'last_posted_at': '2026-09-01T10:00:00.000Z',
        'message_bus_last_id': 100,
        'closed': false,
        'archived': false,
        'visible': true,
        'details': {'can_create_post': true, 'notification_level': 1},
      });
    }
    if (path == '/t/$_topicId/posts.json') {
      final ids = [
        for (final value in request.url.queryParametersAll['post_ids[]']!)
          int.parse(value),
      ];
      postReads.add(ids);
      return _json({
        'post_stream': {
          'posts': [for (final id in ids) _postJson(id)],
        },
        'id': _topicId,
      });
    }
    throw StateError('Unexpected request: $path');
  }

  http.Response _json(Map<String, Object?> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

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
}

Map<String, Object?> _postJson(int id) => {
  'id': id,
  'name': 'Sam',
  'username': 'sam',
  'avatar_template': '/user_avatar/meta.discourse.org/sam/{size}/1_2.png',
  'created_at': '2026-09-01T10:00:00.000Z',
  'cooked': '<p>Short reply $id</p>',
  'post_number': id,
  'post_type': 1,
  'updated_at': '2026-09-01T10:00:00.000Z',
  'reply_count': 0,
  'reply_to_post_number': null,
  'quote_count': 0,
  'incoming_link_count': 0,
  'reads': 1,
  'score': 0,
  'yours': false,
  'topic_id': _topicId,
  'topic_slug': 'a',
  'version': 1,
  'can_edit': false,
  'can_delete': false,
  'can_recover': false,
  'read': false,
  'user_title': null,
  'actions_summary': const <Object>[],
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
};

/// `Post#publish_change_to_clients!(:created)`.
Map<String, Object?> _created(int id) => {
  'id': id,
  'post_number': id,
  'updated_at': '2026-09-01T10:01:00.000Z',
  'user_id': _authorId,
  'last_editor_id': _authorId,
  'type': 'created',
  'version': 1,
  'username': 'sam',
};

/// `Topic.publish_stats_to_clients!(:created)`, published right after it.
Map<String, Object?> _stats(int postsCount) => {
  'posts_count': postsCount,
  'last_posted_at': '2026-09-01T10:01:00.000Z',
  'last_poster': {
    'id': _authorId,
    'username': 'sam',
    'name': 'Sam',
    'avatar_template': '/user_avatar/meta.discourse.org/sam/{size}/1_2.png',
  },
  'id': _topicId,
  'updated_at': '2026-09-01T10:01:00.000Z',
  'type': 'stats',
};

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

Future<({ShellController shell, _Forum forum, FakeSiteTracker tracker})> _open(
  int posts,
) async {
  final forum = _Forum(posts);
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org', user: forum.user),
    ]),
    api: forum,
    authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  shell.pushContent(
    ContentRoute.topic(topicId: _topicId, slug: 'a', title: 'A topic'),
  );
  await shell.loadTopic(_topicId, 'a');
  await _settle();
  expect(forum.fullReads, 1);
  return (shell: shell, forum: forum, tracker: FakeSiteTracker.built.single);
}

void _publish(_Forum forum, FakeSiteTracker tracker, Iterable<int> ids) {
  for (final id in ids) {
    forum.stream.add(id);
    tracker.deliverTopicMessage('/topic/$_topicId', _created(id));
    tracker.deliverTopicMessage(
      '/topic/$_topicId',
      _stats(forum.stream.length),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void report(String shape, _Forum forum) {
    final fullReads = forum.fullReads - 1;
    // ignore: avoid_print
    print('PERF_PROOF live-created ${shape}_full_reads=$fullReads');
    // ignore: avoid_print
    print(
      'PERF_PROOF live-created ${shape}_post_reads=${forum.postReads.length}',
    );
  }

  test('a reply at the loaded end of a topic reads one post', () async {
    final (:shell, :forum, :tracker) = await _open(5);

    _publish(forum, tracker, [6]);
    await _settle();

    report('tail', forum);
    expect(forum.fullReads - 1, 0);
    expect(forum.postReads, [
      [6],
    ]);
    expect(shell.currentTopic?.stream, [1, 2, 3, 4, 5, 6]);
    expect(shell.currentTopic?.postsCount, 6);
    expect(shell.store.read<Post>(_siteUrl, 6)?.username, 'sam');
  });

  test('a burst of replies at the loaded end reads them together', () async {
    final (:shell, :forum, :tracker) = await _open(5);

    _publish(forum, tracker, [6, 7, 8]);
    await _settle();

    report('burst', forum);
    expect(forum.fullReads - 1, 0);
    expect(forum.postReads, [
      [6, 7, 8],
    ]);
    expect(shell.currentTopic?.stream, [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(shell.currentTopic?.postsCount, 8);
  });

  test('a reply past the loaded posts reads nothing', () async {
    final (:shell, :forum, :tracker) = await _open(40);

    _publish(forum, tracker, [41]);
    await _settle();

    report('unloaded', forum);
    expect(forum.fullReads - 1, 0);
    expect(forum.postReads, isEmpty);
    expect(shell.currentTopic?.stream.last, 41);
    expect(shell.currentTopic?.postsCount, 41);
    expect(shell.store.read<Post>(_siteUrl, 41), isNull);
  });
}
