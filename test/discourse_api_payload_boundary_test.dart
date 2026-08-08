import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const siteUrl = 'https://example.com';

MockClient serving(Object? Function(http.Request request) payload) =>
    MockClient(
      (request) async => http.Response(jsonEncode(payload(request)), 200),
    );

void main() {
  test('list endpoints skip malformed optional records', () async {
    final api = DiscourseApi(
      client: serving(
        (request) => switch (request.url.path) {
          '/notifications.json' => {
            'notifications': [
              false,
              {'id': 1},
            ],
          },
          '/u/sam/user-menu-bookmarks.json' => {
            'notifications': [
              'not an object',
              {'id': 2},
            ],
            'bookmarks': [
              42,
              {'id': 3},
            ],
          },
          '/t/7/posts.json' => {
            'post_stream': {
              'posts': [
                null,
                {'id': 4},
              ],
            },
          },
          '/categories.json' => {
            'category_list': {
              'categories': [
                'not an object',
                {
                  'id': 5,
                  'name': 'Parent',
                  'subcategory_list': [
                    false,
                    {'id': 6, 'name': 'Child'},
                  ],
                },
              ],
            },
          },
          _ => throw StateError('Unexpected request: ${request.url}'),
        },
      ),
    );

    final notifications = await api.notifications(
      siteUrl: siteUrl,
      apiKey: 'key',
    );
    final bookmarks = await api.bookmarks(
      siteUrl: siteUrl,
      apiKey: 'key',
      username: 'sam',
    );
    final posts = await api.posts(siteUrl: siteUrl, topicId: 7, ids: const [4]);
    final categories = await api.categories(siteUrl: siteUrl);

    expect(notifications.single.id, 1);
    expect(bookmarks.reminders.single.id, 2);
    expect(bookmarks.bookmarks.single.id, 3);
    expect(posts.single.id, 4);
    expect(categories.map((category) => category.id), [5, 6]);
    expect(() => notifications.clear(), throwsUnsupportedError);
    expect(() => bookmarks.reminders.clear(), throwsUnsupportedError);
    expect(() => bookmarks.bookmarks.clear(), throwsUnsupportedError);
    expect(() => posts.clear(), throwsUnsupportedError);
    expect(() => categories.clear(), throwsUnsupportedError);
  });

  test('optional mention and chat envelopes default or skip safely', () async {
    final api = DiscourseApi(
      client: serving(
        (request) => switch (request.url.path) {
          '/composer/mentions' => {
            'users': [42, 'sam'],
            'groups': ['not an object'],
          },
          '/chat/api/channels/9/messages.json' => {
            'meta': ['not an object'],
            'messages': [
              false,
              {
                'id': 7,
                'chat_channel_id': 9,
                'cooked': 42,
                'user': ['not an object'],
                'in_reply_to': ['not an object'],
                'thread': ['not an object'],
                'reactions': [
                  false,
                  {'emoji': 42, 'count': 1},
                ],
                'uploads': [
                  false,
                  {
                    'url': 42,
                    'original_filename': true,
                    'thumbnail': ['not an object'],
                  },
                ],
              },
              {
                'id': 8,
                'chat_channel_id': 9,
                'in_reply_to': {
                  'id': 7,
                  'user': ['not an object'],
                },
                'thread': {
                  'id': 4,
                  'preview': ['not an object'],
                },
              },
            ],
          },
          _ => throw StateError('Unexpected request: ${request.url}'),
        },
      ),
    );

    final mentions = await api.checkMentions(
      siteUrl: siteUrl,
      names: const ['sam'],
    );
    final page = await api.chatMessages(siteUrl: siteUrl, channelId: 9);

    expect(mentions, {'sam'});
    expect(page.canLoadMorePast, isFalse);
    expect(page.canLoadMoreFuture, isFalse);
    expect(page.messages, hasLength(2));
    expect(page.messages.first.cooked, '');
    expect(page.messages.first.author.username, '');
    expect(page.messages.first.replyTo, isNull);
    expect(page.messages.first.thread, isNull);
    expect(page.messages.first.reactions.single.emoji, '');
    expect(page.messages.first.uploads.single.url, '');
    expect(page.messages.first.uploads.single.thumbnailUrl, isNull);
    expect(page.messages.last.replyTo?.username, '');
    expect(page.messages.last.thread?.threadId, 4);
    expect(page.messages.last.thread?.lastReplyUsername, isNull);
    expect(() => page.messages.clear(), throwsUnsupportedError);
    expect(() => page.messages.first.reactions.clear(), throwsUnsupportedError);
    expect(() => page.messages.first.uploads.clear(), throwsUnsupportedError);
  });

  test('required user envelopes fail through the read contract', () async {
    final api = DiscourseApi(
      client: serving(
        (request) => switch (request.url.path) {
          '/session/current.json' => {
            'current_user': ['not an object'],
          },
          '/u/sam/card.json' => {
            'user': ['not an object'],
          },
          _ => throw StateError('Unexpected request: ${request.url}'),
        },
      ),
    );

    await expectLater(
      api.currentUser(siteUrl: siteUrl, apiKey: 'key'),
      throwsA(isA<SiteLookupException>()),
    );
    await expectLater(
      api.userCard(siteUrl: siteUrl, username: 'sam'),
      throwsA(isA<SiteLookupException>()),
    );
  });

  test('malformed optional user fields use model defaults', () async {
    final api = DiscourseApi(
      client: serving(
        (request) => switch (request.url.path) {
          '/session/current.json' => {
            'current_user': {
              'username': 'sam',
              'name': 42,
              'avatar_template': ['not a string'],
            },
          },
          '/u/sam/card.json' => {
            'user': {
              'username': 'sam',
              'title': 42,
              'avatar_template': ['not a string'],
            },
          },
          _ => throw StateError('Unexpected request: ${request.url}'),
        },
      ),
    );

    final current = await api.currentUser(siteUrl: siteUrl, apiKey: 'key');
    final card = await api.userCard(siteUrl: siteUrl, username: 'sam');

    expect(current.username, 'sam');
    expect(current.name, isNull);
    expect(current.avatarUrl, isNull);
    expect(card.username, 'sam');
    expect(card.title, isNull);
    expect(card.avatarUrl, isNull);
  });
}
