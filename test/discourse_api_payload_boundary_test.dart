import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
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

  test('user-menu payloads cannot exceed their route budgets', () async {
    var requestCount = 0;
    final api = DiscourseApi(
      client: serving((request) {
        requestCount += 1;
        return switch (request.url.path) {
          '/notifications.json' => {
            'notifications': [
              for (var id = 1; id <= 65; id++) {'id': id},
            ],
          },
          '/u/sam/user-menu-bookmarks.json' => {
            'notifications': [
              for (var id = 1; id <= 3; id++) {'id': id},
            ],
            'bookmarks': [
              for (var id = 1; id <= 25; id++) {'id': id},
            ],
          },
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      }),
    );

    final notifications = await api.notifications(
      siteUrl: siteUrl,
      apiKey: 'key',
      limit: DiscourseApi.maximumRecentNotifications,
    );
    final bookmarks = await api.bookmarks(
      siteUrl: siteUrl,
      apiKey: 'key',
      username: 'sam',
    );

    expect(notifications, hasLength(60));
    expect(notifications.last.id, 60);
    expect(bookmarks.reminders, hasLength(3));
    expect(bookmarks.bookmarks, hasLength(17));
    expect(bookmarks.bookmarks.last.id, 17);

    await expectLater(
      api.notifications(siteUrl: siteUrl, apiKey: 'key', limit: 61),
      throwsRangeError,
    );
    expect(requestCount, 2, reason: 'invalid limits fail before transport');
  });

  test('draft pages cannot exceed their requested local budget', () async {
    var requestCount = 0;
    final api = DiscourseApi(
      client: serving((request) {
        requestCount += 1;
        expect(request.url.queryParameters, {
          'offset': '0',
          'limit': '${DiscourseApi.maximumUserDraftPageSize}',
        });
        return {
          'drafts': [
            for (var id = 1; id <= 35; id++)
              {'draft_key': 'topic_$id', 'sequence': id},
          ],
        };
      }),
    );

    final drafts = await api.userDrafts(
      siteUrl: siteUrl,
      apiKey: 'key',
      limit: DiscourseApi.maximumUserDraftPageSize,
    );

    expect(drafts, hasLength(30));
    expect(drafts.last.key, 'topic_30');
    await expectLater(
      api.userDrafts(siteUrl: siteUrl, apiKey: 'key', offset: -1),
      throwsRangeError,
    );
    await expectLater(
      api.userDrafts(siteUrl: siteUrl, apiKey: 'key', limit: 0),
      throwsRangeError,
    );
    await expectLater(
      api.userDrafts(siteUrl: siteUrl, apiKey: 'key', limit: 31),
      throwsRangeError,
    );
    expect(requestCount, 1, reason: 'invalid pages fail before transport');
  });

  test(
    'activity pages keep their raw server budget and validate bounds',
    () async {
      var requestCount = 0;
      final api = DiscourseApi(
        client: serving((request) {
          requestCount += 1;
          expect(request.url.queryParameters, {
            'offset': '0',
            'username': 'sam',
            'filter': '4,5',
            'limit': '${DiscourseApi.maximumUserActivityPageSize}',
          });
          return {
            'user_actions': [
              for (
                var id = 1;
                id <= DiscourseApi.maximumUserActivityPageSize + 5;
                id++
              )
                {
                  'action_type': id.isEven ? 5 : 4,
                  'topic_id': id,
                  'post_number': id.isEven ? 2 : 1,
                  'title': 'Activity $id',
                },
            ],
          };
        }),
      );

      final page = await api.userActivity(
        siteUrl: siteUrl,
        apiKey: 'key',
        username: 'sam',
        limit: DiscourseApi.maximumUserActivityPageSize,
      );

      expect(page.items, hasLength(DiscourseApi.maximumUserActivityPageSize));
      expect(page.rawItemCount, DiscourseApi.maximumUserActivityPageSize);
      await expectLater(
        api.userActivity(
          siteUrl: siteUrl,
          apiKey: 'key',
          username: 'sam',
          offset: -1,
        ),
        throwsRangeError,
      );
      await expectLater(
        api.userActivity(
          siteUrl: siteUrl,
          apiKey: 'key',
          username: 'sam',
          limit: 0,
        ),
        throwsRangeError,
      );
      await expectLater(
        api.userActivity(
          siteUrl: siteUrl,
          apiKey: 'key',
          username: 'sam',
          limit: DiscourseApi.maximumUserActivityPageSize + 1,
        ),
        throwsRangeError,
      );
      expect(requestCount, 1, reason: 'invalid pages fail before transport');
    },
  );

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
    final page = await ChatApiClient(
      api,
    ).chatMessages(siteUrl: siteUrl, channelId: 9);

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
