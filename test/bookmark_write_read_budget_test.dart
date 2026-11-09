import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/bookmark.dart';
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
const _postCount = 20;

final class _Read {
  _Read(this.path, this.bytes);
  final String path;
  final int bytes;
}

/// One topic behind the real HTTP client, answering as `TopicViewSerializer`,
/// `PostSerializer`, `BookmarksController` and the user-menu bookmark route do.
final class _Forum extends FakeDiscourseApi {
  _Forum()
    : super(
        user: const DiscourseUser(id: 1, username: 'reader'),
        feeds: const {
          '/latest.json': [Topic(id: _topicId, title: 'A topic', slug: 'a')],
        },
      );

  final reads = <_Read>[];
  final writes = <String>[];
  final held = <int, Map<String, Object?>>{};
  var nextBookmark = 91;

  late final _client = DiscourseApi(client: MockClient(_answer));

  Iterable<String> get topicReads =>
      reads.map((read) => read.path).where((path) => path.startsWith('/t/'));

  int get topicReadBytes => reads
      .where((read) => read.path.startsWith('/t/'))
      .fold(0, (total, read) => total + read.bytes);

  Iterable<String> get menuReads => reads
      .map((read) => read.path)
      .where((path) => path.endsWith('/user-menu-bookmarks.json'));

  Future<http.Response> _answer(http.Request request) async {
    final path = request.url.path;
    if (request.method != 'GET') {
      writes.add('${request.method} $path');
      return _write(request);
    }
    final response = switch (path) {
      '/t/$_topicId.json' => _json(_topic()),
      '/u/reader/user-menu-bookmarks.json' => _json({
        'notifications': const <Object>[],
        'bookmarks': [for (final row in held.values) row],
      }),
      _ => throw StateError('Unexpected request: GET $path'),
    };
    reads.add(_Read(path, response.bodyBytes.length));
    return response;
  }

  http.Response _write(http.Request request) {
    final path = request.url.path;
    if (path == '/bookmarks.json') {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final id = nextBookmark++;
      held[id] = {
        'id': id,
        'bookmarkable_id': body['bookmarkable_id'],
        'bookmarkable_type': body['bookmarkable_type'],
        'name': body['name'],
        'reminder_at': body['reminder_at'],
        'auto_delete_preference': body['auto_delete_preference'],
      };
      return _json({'success': 'OK', 'id': id});
    }
    if (path == '/t/$_topicId/remove_bookmarks') {
      held.clear();
      return _json({'success': 'OK'});
    }
    final id = int.parse(RegExp(r'/bookmarks/(\d+)').firstMatch(path)![1]!);
    if (request.method == 'DELETE') {
      held.remove(id);
      return _json({'success': 'OK', 'topic_bookmarked': held.isNotEmpty});
    }
    final body = jsonDecode(request.body) as Map<String, Object?>;
    held[id] = {...held[id]!, 'name': body['name']};
    return _json({'success': 'OK'});
  }

  http.Response _json(Map<String, Object?> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, Object?> _topic() => {
    'post_stream': {
      'posts': [for (var id = 1; id <= _postCount; id++) _post(id)],
      'stream': [for (var id = 1; id <= _postCount; id++) id],
    },
    'id': _topicId,
    'title': 'A topic',
    'fancy_title': 'A topic',
    'slug': 'a',
    'posts_count': _postCount,
    'highest_post_number': _postCount,
    'last_posted_at': '2026-09-01T10:00:00.000Z',
    'message_bus_last_id': 100,
    'closed': false,
    'archived': false,
    'visible': true,
    'bookmarked': held.isNotEmpty,
    'bookmarks': [
      for (final row in held.values)
        {
          'id': row['id'],
          'bookmarkable_id': row['bookmarkable_id'],
          'bookmarkable_type': row['bookmarkable_type'],
          'name': row['name'],
          'reminder_at': row['reminder_at'],
          'auto_delete_preference': row['auto_delete_preference'],
          if (row['bookmarkable_type'] == 'Post')
            'post_number': row['bookmarkable_id'],
        },
    ],
    'details': {'can_create_post': true, 'notification_level': 1},
  };

  Map<String, Object?> _post(int id) {
    final row = held.values
        .where(
          (row) =>
              row['bookmarkable_type'] == 'Post' &&
              row['bookmarkable_id'] == id,
        )
        .firstOrNull;
    return {
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
      'version': 1,
      'can_edit': false,
      'can_delete': false,
      'can_recover': false,
      'read': true,
      'user_title': null,
      'bookmarked': row != null,
      if (row != null) ...{
        'bookmark_id': row['id'],
        'bookmark_name': row['name'],
        'bookmark_reminder_at': row['reminder_at'],
        'bookmark_auto_delete_preference': row['auto_delete_preference'],
      },
      'actions_summary': const [
        {'id': 2, 'count': 3, 'can_act': true},
      ],
      'moderator': false,
      'admin': false,
      'staff': false,
      'user_id': 9,
      'hidden': false,
      'trust_level': 1,
      'deleted_at': null,
      'user_deleted': false,
      'edit_reason': null,
      'can_view_edit_history': true,
      'wiki': false,
    };
  }

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
  }) => _client.topic(
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
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) => _client.bookmarks(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    clientId: clientId,
  );

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) => _client.createBookmark(
    siteUrl: siteUrl,
    apiKey: apiKey,
    targetType: targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
    clientId: clientId,
  );

  @override
  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    DateTime? originalReminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) => _client.updateBookmark(
    siteUrl: siteUrl,
    apiKey: apiKey,
    bookmarkId: bookmarkId,
    name: name,
    reminderAt: reminderAt,
    originalReminderAt: originalReminderAt,
    autoDeletePreference: autoDeletePreference,
    clientId: clientId,
  );

  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) => _client.deleteBookmark(
    siteUrl: siteUrl,
    apiKey: apiKey,
    bookmarkId: bookmarkId,
    targetType: targetType,
    clientId: clientId,
  );

  @override
  Future<void> deleteTopicBookmarks({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) => _client.deleteTopicBookmarks(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    clientId: clientId,
  );
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

Future<({ShellController shell, _Forum forum})> _open() async {
  final forum = _Forum();
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
  expect(forum.topicReads, hasLength(1));
  forum.reads.clear();
  return (shell: shell, forum: forum);
}

void _report(String shape, _Forum forum) {
  // ignore: avoid_print
  print(
    'PERF_PROOF bookmark-write ${shape}_topic_reads=${forum.topicReads.length}',
  );
  // ignore: avoid_print
  print(
    'PERF_PROOF bookmark-write ${shape}_topic_bytes=${forum.topicReadBytes}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saving a post bookmark does not read the topic', () async {
    final (:shell, :forum) = await _open();

    final result = await shell.createBookmark(
      siteUrl: _siteUrl,
      topicId: _topicId,
      targetType: BookmarkTargetType.post,
      targetId: 2,
      name: 'Read this',
    );
    await _settle();

    _report('create_post', forum);
    expect(result.saved, isTrue);
    expect(forum.writes, ['POST /bookmarks.json']);
    expect(forum.topicReads, isEmpty);
    final bookmark = shell.store.read<Post>(_siteUrl, 2)?.bookmark;
    expect(bookmark?.id, 91);
    expect(bookmark?.name, 'Read this');
    expect(bookmark?.postNumber, 2);
    expect(
      shell.store
          .read<TopicDetail>(_siteUrl, _topicId)
          ?.postBookmarks
          .map((held) => held.id),
      [91],
    );
    expect(shell.store.read<Topic>(_siteUrl, _topicId)?.bookmarked, isTrue);
  });

  test('saving a topic bookmark does not read the topic', () async {
    final (:shell, :forum) = await _open();

    final result = await shell.createBookmark(
      siteUrl: _siteUrl,
      topicId: _topicId,
      targetType: BookmarkTargetType.topic,
      targetId: _topicId,
    );
    await _settle();

    _report('create_topic', forum);
    expect(result.saved, isTrue);
    expect(forum.topicReads, isEmpty);
    expect(
      shell.store.read<TopicDetail>(_siteUrl, _topicId)?.topicBookmark?.id,
      91,
    );
    expect(shell.store.read<Topic>(_siteUrl, _topicId)?.bookmarked, isTrue);
  });

  test('editing a bookmark does not read the topic', () async {
    final (:shell, :forum) = await _open();
    final created = await shell.createBookmark(
      siteUrl: _siteUrl,
      topicId: _topicId,
      targetType: BookmarkTargetType.post,
      targetId: 2,
    );
    await _settle();
    forum.reads.clear();

    final result = await shell.updateBookmark(
      siteUrl: _siteUrl,
      topicId: _topicId,
      bookmark: created.bookmark!,
      name: 'Renamed',
      autoDeletePreference: BookmarkAutoDeletePreference.never,
    );
    await _settle();

    _report('update', forum);
    expect(result.saved, isTrue);
    expect(forum.writes.last, 'PUT /bookmarks/91.json');
    expect(forum.topicReads, isEmpty);
    expect(shell.store.read<Post>(_siteUrl, 2)?.bookmark?.name, 'Renamed');
  });

  test('deleting a bookmark does not read the topic', () async {
    final (:shell, :forum) = await _open();
    final created = await shell.createBookmark(
      siteUrl: _siteUrl,
      topicId: _topicId,
      targetType: BookmarkTargetType.post,
      targetId: 2,
    );
    await _settle();
    forum.reads.clear();

    final result = await shell.deleteBookmark(
      siteUrl: _siteUrl,
      topicId: _topicId,
      bookmark: created.bookmark!,
    );
    await _settle();

    _report('delete', forum);
    expect(result.saved, isTrue);
    expect(forum.writes.last, 'DELETE /bookmarks/91.json');
    expect(forum.topicReads, isEmpty);
    expect(shell.store.read<Post>(_siteUrl, 2)?.bookmark, isNull);
    expect(shell.store.read<Topic>(_siteUrl, _topicId)?.bookmarked, isFalse);
  });

  test('clearing a topic\'s bookmarks does not read the topic', () async {
    final (:shell, :forum) = await _open();
    await shell.createBookmark(
      siteUrl: _siteUrl,
      topicId: _topicId,
      targetType: BookmarkTargetType.post,
      targetId: 2,
    );
    await _settle();
    forum.reads.clear();

    final result = await shell.deleteAllTopicBookmarks(
      siteUrl: _siteUrl,
      topicId: _topicId,
    );
    await _settle();

    _report('clear', forum);
    expect(result.saved, isTrue);
    expect(forum.writes.last, 'PUT /t/$_topicId/remove_bookmarks');
    expect(forum.topicReads, isEmpty);
    expect(shell.store.read<Post>(_siteUrl, 2)?.bookmark, isNull);
    expect(
      shell.store.read<TopicDetail>(_siteUrl, _topicId)?.bookmarks,
      isEmpty,
    );
  });

  test(
    'a saved post this account does not hold is numbered by a read',
    () async {
      final (:shell, :forum) = await _open();

      shell.store.remove<Post>(_siteUrl, 16);

      final unheld = await shell.createBookmark(
        siteUrl: _siteUrl,
        topicId: _topicId,
        targetType: BookmarkTargetType.post,
        targetId: 16,
      );
      await _settle();

      expect(unheld.saved, isTrue);
      expect(forum.topicReads, hasLength(1));
      expect(
        shell.store
            .read<TopicDetail>(_siteUrl, _topicId)
            ?.postBookmarks
            .firstWhere((held) => held.bookmarkableId == 16)
            .postNumber,
        16,
      );
    },
  );
}
