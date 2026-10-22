import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/chat/chat_global_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:flutter_test/flutter_test.dart';

const site = 'https://example.com';

Map<String, dynamic> result(int id, {int channelId = 9}) => {
  'id': id,
  'chat_channel_id': channelId,
  'cooked': '<p>message $id</p>',
  'excerpt': 'message $id',
  'created_at': '2026-08-25T10:00:00Z',
  'user': {'id': 2, 'username': 'sam'},
  'channel': {
    'id': channelId,
    'title': 'Bugs',
    'chatable_type': 'Category',
    'chatable': {'color': '0088CC'},
  },
};

Future<GlobalSearchPage> globalPage(Map<String, dynamic> body) =>
    const ChatGlobalSearch().search(
      GlobalSearchReadContext(
        siteUrl: site,
        authenticated: true,
        get: (_) async => body,
      ),
      GlobalSearchRequest(
        scope: chatSearchScope,
        query: 'message',
        capabilities: const GlobalSearchCapabilities(authenticated: true),
      ),
    );

void main() {
  test(
    'both searches accept the same bounded window and consume rejected objects',
    () async {
      final body = <String, dynamic>{
        'messages': [
          null,
          'not a row',
          for (final id in [0, -1, null, 'bad']) {...result(1), 'id': id},
          {...result(2), 'channel': null},
          {...result(3), 'channel': 'bad'},
          {...result(4), 'chat_channel_id': 10},
          {
            ...result(5),
            'chat_channel_id': 0,
            'channel': {'id': 0},
          },
          {
            ...result(6),
            'chat_channel_id': -1,
            'channel': {'id': -1},
          },
          {...result(7), 'chat_channel_id': 'bad'},
          {
            ...result(8),
            'channel': {'id': 'bad'},
          },
          {
            ...result(9),
            'id': '9',
            'chat_channel_id': '9',
            'channel': {'id': '9'},
          },
          for (var id = 10; id < 50; id++) result(id),
        ],
        'meta': {'has_more': true, 'offset': 60, 'limit': 40},
      };
      final dedicated = ChatSearchPage.fromJson(body, site);
      final global = await globalPage(body);
      final expected = [for (var id = 9; id <= 37; id++) id];
      expect(dedicated.hits.map((hit) => hit.id), expected);
      expect(
        global.results.map((hit) => hit.id),
        expected.map((id) => 'chat:$id'),
      );
      expect(dedicated.consumedCount, 40);
      expect(global.consumedCount, 40);
      expect(dedicated.hasMore, isTrue);
      expect(global.hasMore, isTrue);
      expect(global.sections.single.hasMore, isTrue);
    },
  );

  test(
    'both searches consume rejected pages and tolerate malformed envelopes',
    () async {
      for (final messages in [
        null,
        'bad',
        [null, false],
        [
          <String, dynamic>{},
          {...result(1), 'chat_channel_id': 10},
        ],
      ]) {
        final body = {
          'messages': messages,
          'meta': {'has_more': true},
        };
        final dedicated = ChatSearchPage.fromJson(body, site);
        final global = await globalPage(body);
        expect(dedicated.hits, isEmpty);
        expect(global.results, isEmpty);
        final consumed = messages is List && messages.lastOrNull is Map ? 2 : 0;
        expect(dedicated.consumedCount, consumed);
        expect(global.consumedCount, consumed);
        expect(dedicated.hasMore, isTrue);
        expect(global.hasMore, isTrue);
      }
    },
  );

  test(
    'paging metadata retains coercion, clamping and strict boolean semantics',
    () async {
      for (final fixture in [
        (meta: null, more: false, limit: 20, offset: 0),
        (meta: 'bad', more: false, limit: 20, offset: 0),
        (
          meta: {'has_more': 'true', 'limit': 0, 'offset': -1},
          more: false,
          limit: 1,
          offset: 0,
        ),
        (
          meta: {'has_more': true, 'limit': '100', 'offset': '41'},
          more: true,
          limit: 40,
          offset: 41,
        ),
        (
          meta: {'has_more': 1, 'limit': 'bad', 'offset': 'bad'},
          more: false,
          limit: 20,
          offset: 0,
        ),
      ]) {
        final body = {
          'messages': [result(1)],
          'meta': fixture.meta,
        };
        final dedicated = ChatSearchPage.fromJson(body, site);
        final global = await globalPage(body);
        expect(dedicated.hasMore, fixture.more);
        expect(global.hasMore, fixture.more);
        expect(dedicated.limit, fixture.limit);
        expect(dedicated.offset, fixture.offset);
      }
    },
  );

  test(
    'each search retains its presentation fallbacks and thread identity',
    () async {
      final body = <String, dynamic>{
        'messages': [
          {
            ...result(1),
            'username': 'fallback',
            'user': {
              'username': ' nested ',
              'name': ' Name ',
              'avatar_template': '/avatar/{size}.png',
            },
            'channel': {
              'id': 9,
              'unicode_title': 'Unicode',
              'title': ' Title ',
              'name': 'Name',
              'slug': 'a/b c',
            },
            'thread_id': 7,
            'thread_title': ' Search title ',
            'thread': {'id': 7, 'title': 'Nested title'},
            'excerpt': ' <b>Excerpt</b> ',
          },
          {
            ...result(2),
            'username': ' fallback ',
            'user': {'username': ' ', 'name': ' '},
            'channel': {'id': 9, 'name': ' Channel name '},
            'thread_id': 0,
            'thread': {'id': 8, 'title': 'Nested title'},
            'excerpt': ' ',
            'cooked': '<p>Cooked</p>',
          },
          {
            ...result(3),
            'user': null,
            'username': 'raw-user',
            'channel': {'id': 9, 'slug': 'slug'},
            'thread_id': -1,
            'excerpt': null,
            'cooked': '',
            'message': 'Raw message',
          },
          {
            ...result(4),
            'user': <String, dynamic>{},
            'channel': {'id': 9},
            'thread_id': null,
            'excerpt': null,
            'cooked': null,
            'message': null,
          },
        ],
      };
      final dedicated = ChatSearchPage.fromJson(body, site);
      final global = await globalPage(body);
      expect(dedicated.hits.map((h) => h.channel.title), [
        'Unicode',
        '',
        '',
        '',
      ]);
      expect(dedicated.hits.map((h) => h.message.author.username), [
        ' nested ',
        ' ',
        '',
        '',
      ]);
      expect(dedicated.hits.map((h) => h.threadTitle), [
        'Search title',
        'Nested title',
        null,
        null,
      ]);
      expect(dedicated.hits.map((h) => h.message.threadId), [7, 0, -1, null]);
      expect(dedicated.hits.map((h) => h.excerpt), [
        '<b>Excerpt</b>',
        null,
        null,
        null,
      ]);
      final results = global.results.toList();
      expect(results.map((r) => r.title), ['Name', 'fallback', 'raw-user', '']);
      expect(results.map((r) => r.username), [
        'nested',
        'fallback',
        'raw-user',
        '',
      ]);
      expect(results.map((r) => r.contextLabel), [
        '# Title',
        '# Channel name',
        '# slug',
        '# ',
      ]);
      expect(results.map((r) => r.excerpt), [
        'Excerpt',
        'Cooked',
        'Raw message',
        '',
      ]);
      expect(results.map((r) => r.path), [
        '/chat/c/a%2Fb%20c/9/t/7/1',
        '/chat/c/-/9/2',
        '/chat/c/slug/9/3',
        '/chat/c/-/9/4',
      ]);
      expect(results.map((r) => r.destination!.identity), [
        const ExtensionDestination('chat-c-9-t-7').identity,
        for (var i = 0; i < 3; i++)
          const ExtensionDestination('chat-c-9').identity,
      ]);
      expect(
        results.first.avatarUrl,
        resolveAvatarUrl('/avatar/{size}.png', site),
      );
      expect(results.skip(1).map((r) => r.avatarUrl), everyElement(isNull));
      expect(results.first.createdAt, DateTime.utc(2026, 8, 25, 10));
    },
  );

  test('parses message, channel, thread context, and paging metadata', () {
    final json = result(40)
      ..['thread_id'] = 7
      ..['thread_title'] = 'Search design';

    final page = ChatSearchPage.fromJson({
      'messages': [json],
      'meta': const {'has_more': true, 'limit': 20, 'offset': 40},
    }, site);

    expect(page.hits.single.message.id, 40);
    expect(page.hits.single.channel.title, 'Bugs');
    expect(page.hits.single.threadTitle, 'Search design');
    expect(page.hits.single.excerpt, 'message 40');
    expect(page.hasMore, isTrue);
    expect(page.limit, 20);
    expect(page.offset, 40);
    expect(page.consumedCount, 1);
  });

  test('bounds work and drops partial or mismatched result records', () {
    final messages = [for (var id = 1; id <= 45; id++) result(id)];
    messages[0].remove('channel');
    messages[1]['chat_channel_id'] = 10;

    final page = ChatSearchPage.fromJson({'messages': messages}, site);

    expect(page.hits.map((hit) => hit.id), [
      for (var id = 3; id <= ChatSearchPage.maximumPageSize; id++) id,
    ]);
    expect(page.limit, ChatSearchPage.defaultPageSize);
    expect(page.offset, 0);
    expect(page.consumedCount, ChatSearchPage.maximumPageSize);
  });
}
