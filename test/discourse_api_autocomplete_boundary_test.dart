import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/poll/poll_api.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'chat paging retains the response edge adjacent to its target',
    () async {
      final api = DiscourseApi(
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'messages': [
                for (var id = 1; id <= 12; id++)
                  {
                    'id': id,
                    'chat_channel_id': 1,
                    'cooked': '<p>$id</p>',
                    'user': {'id': 1, 'username': 'reader'},
                  },
              ],
              'meta': const <String, dynamic>{},
            }),
            200,
          );
        }),
      );

      final past = await ChatApiClient(api).chatMessages(
        siteUrl: 'https://example.com',
        channelId: 1,
        before: 13,
        pageSize: 5,
      );
      final future = await ChatApiClient(api).chatMessages(
        siteUrl: 'https://example.com',
        channelId: 1,
        after: 0xCAFE,
        pageSize: 5,
      );

      expect(past.messages.map((entry) => entry.id), [8, 9, 10, 11, 12]);
      expect(past.canLoadMorePast, isTrue);
      expect(future.messages.map((entry) => entry.id), [1, 2, 3, 4, 5]);
      expect(future.canLoadMoreFuture, isTrue);
    },
  );

  test(
    'chat writes reject invalid identities and blank messages before transport',
    () async {
      var calls = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );

      final invalidCalls = <({String reason, Future<void> Function() call})>[
        (
          reason: 'zero channel id for a channel read',
          call: () => ChatApiClient(api).markChatChannelRead(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            channelId: 0,
            messageId: 1,
          ),
        ),
        (
          reason: 'negative message id for a channel read',
          call: () => ChatApiClient(api).markChatChannelRead(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            channelId: 1,
            messageId: -1,
          ),
        ),
        (
          reason: 'negative channel id for a send',
          call: () async {
            await ChatApiClient(api).sendChatMessage(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              channelId: -1,
              message: 'hello',
            );
          },
        ),
        (
          reason: 'blank message for a send',
          call: () async {
            await ChatApiClient(api).sendChatMessage(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              channelId: 1,
              message: '   ',
            );
          },
        ),
        (
          reason: 'zero thread id for a send',
          call: () async {
            await ChatApiClient(api).sendChatMessage(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              channelId: 1,
              threadId: 0,
              message: 'hello',
            );
          },
        ),
        (
          reason: 'zero thread id for a thread read',
          call: () => ChatApiClient(api).markChatThreadRead(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            channelId: 1,
            threadId: 0,
            messageId: 2,
          ),
        ),
        (
          reason: 'zero message id for a thread read',
          call: () => ChatApiClient(api).markChatThreadRead(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            channelId: 1,
            threadId: 2,
            messageId: 0,
          ),
        ),
      ];

      for (final (:reason, :call) in invalidCalls) {
        await expectLater(call(), throwsArgumentError, reason: reason);
      }
      expect(calls, 0);
    },
  );

  test(
    'post and poll writes reject invalid identities and blank reactions before transport',
    () async {
      var calls = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );

      final invalidCalls = <({String reason, Future<void> Function() call})>[
        (
          reason: 'zero topic id for a post create',
          call: () async {
            await api.createPost(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              topicId: 0,
              raw: 'hello',
              typingDuration: Duration.zero,
              composerOpenDuration: Duration.zero,
            );
          },
        ),
        (
          reason: 'zero reply post number for a post create',
          call: () async {
            await api.createPost(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              topicId: 1,
              replyToPostNumber: 0,
              raw: 'hello',
              typingDuration: Duration.zero,
              composerOpenDuration: Duration.zero,
            );
          },
        ),
        (
          reason: 'zero category id for a topic create',
          call: () async {
            await api.createTopic(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              categoryId: 0,
              title: 'Title',
              raw: 'hello',
              typingDuration: Duration.zero,
              composerOpenDuration: Duration.zero,
            );
          },
        ),
        (
          reason: 'zero topic id for a topic update',
          call: () => api.updateTopic(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            topicId: 0,
            title: 'Title',
            originalTitle: 'Old',
            tags: const [],
            originalTags: const [],
          ),
        ),
        (
          reason: 'zero topic id for a tag update',
          call: () => api.updateTopicTags(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            topicId: 0,
            tags: const [],
          ),
        ),
        (
          reason: 'zero post id for a post update',
          call: () async {
            await api.updatePost(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              postId: 0,
              raw: 'hello',
            );
          },
        ),
        (
          reason: 'zero post id for a delete',
          call: () => api.deletePost(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            postId: 0,
          ),
        ),
        (
          reason: 'zero post id for a like',
          call: () async {
            await api.likePost(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              postId: 0,
            );
          },
        ),
        (
          reason: 'zero post id for an unlike',
          call: () async {
            await api.unlikePost(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              postId: 0,
            );
          },
        ),
        (
          reason: 'zero post id for a reaction',
          call: () async {
            await ReactionsApiClient(api, api.models).toggleReaction(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              postId: 0,
              reaction: 'clap',
            );
          },
        ),
        (
          reason: 'blank reaction name',
          call: () async {
            await ReactionsApiClient(api, api.models).toggleReaction(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              postId: 1,
              reaction: '',
            );
          },
        ),
        (
          reason: 'zero post id for a poll vote',
          call: () async {
            await PollApi(api).votePoll(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              postId: 0,
              pollName: 'poll',
              options: const ['a'],
            );
          },
        ),
        (
          reason: 'zero post id for removing a poll vote',
          call: () async {
            await PollApi(api).removePollVote(
              siteUrl: 'https://example.com',
              apiKey: 'key',
              postId: 0,
              pollName: 'poll',
            );
          },
        ),
        (
          reason: 'zero post id for recovery',
          call: () => api.recoverPost(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            postId: 0,
          ),
        ),
      ];

      for (final (:reason, :call) in invalidCalls) {
        await expectLater(call(), throwsArgumentError, reason: reason);
      }
      expect(calls, 0);
    },
  );

  test(
    'user autocomplete validates inputs and retains only its requested page',
    () async {
      var calls = 0;
      late Uri requested;
      final api = DiscourseApi(
        client: MockClient((request) async {
          calls++;
          requested = request.url;
          return http.Response(
            jsonEncode({
              'users': [
                for (var index = 0; index < 25; index++)
                  {'username': 'user-$index'},
              ],
            }),
            200,
          );
        }),
      );

      final users = await api.searchUsers(
        siteUrl: 'https://example.com',
        term: 'user',
        topicId: 7,
        limit: 2,
      );

      expect(users.map((user) => user.username), ['user-0', 'user-1']);
      expect(requested.queryParameters['limit'], '2');
      expect(calls, 1);

      await expectLater(
        api.searchUsers(siteUrl: 'https://example.com', term: 'user', limit: 0),
        throwsRangeError,
      );
      await expectLater(
        api.searchUsers(
          siteUrl: 'https://example.com',
          term: 'user',
          limit: DiscourseApi.maximumAutocompleteResults + 1,
        ),
        throwsRangeError,
      );
      await expectLater(
        api.searchUsers(
          siteUrl: 'https://example.com',
          term: 'user',
          topicId: 0,
        ),
        throwsRangeError,
      );
      await expectLater(
        api.searchUsers(
          siteUrl: 'https://example.com',
          term: 'x' * (DiscourseApi.maximumSearchTermLength + 1),
        ),
        throwsArgumentError,
      );
      expect(calls, 1, reason: 'invalid inputs must fail before transport');
    },
  );

  test('topic-filter lookups bound rows and tag-group descriptions', () async {
    final api = DiscourseApi(
      client: MockClient((request) async {
        final rows = [
          for (var index = 0; index < 25; index++)
            {
              'name': 'value-$index',
              'count': index,
              'full_name': 'Value $index',
              'tags': [
                for (var tag = 0; tag < 25; tag++) {'name': 'tag-$tag'},
              ],
            },
        ];
        return switch (request.url.path) {
          '/groups/search.json' => http.Response(jsonEncode(rows), 200),
          _ => http.Response(jsonEncode({'results': rows}), 200),
        };
      }),
    );

    final tags = await api.searchFilterTags(
      siteUrl: 'https://example.com',
      term: 'v',
      limit: 2,
    );
    final tagGroups = await api.searchFilterTagGroups(
      siteUrl: 'https://example.com',
      term: 'v',
      limit: 2,
    );
    final groups = await api.searchFilterGroups(
      siteUrl: 'https://example.com',
      term: 'v',
      limit: 2,
    );

    expect(tags.map((value) => value.name), ['value-0', 'value-1']);
    expect(tagGroups.map((value) => value.name), ['value-0', 'value-1']);
    expect(groups.map((value) => value.name), ['value-0', 'value-1']);
    expect(tagGroups.first.description?.split(', '), [
      for (
        var index = 0;
        index < DiscourseApi.maximumAutocompleteResults;
        index++
      )
        'tag-$index',
    ]);
  });

  test('topic tag search enforces the shared autocomplete boundary', () async {
    var calls = 0;
    final api = DiscourseApi(
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'results': [
              for (var index = 0; index < 25; index++)
                {'id': index + 1, 'name': 'tag-$index'},
            ],
          }),
          200,
        );
      }),
    );

    final result = await api.searchTopicTags(
      siteUrl: 'https://example.com',
      apiKey: 'key',
      term: 'tag',
      categoryId: 4,
      limit: 2,
    );
    expect(result.tags.map((tag) => tag.name), ['tag-0', 'tag-1']);

    final parsed = TopicTagSearch.fromJson({
      'results': [
        for (var index = 0; index < 25; index++) {'name': 'raw-$index'},
      ],
    });
    expect(parsed.tags, hasLength(TopicTagSearch.maximumResults));
    expect(parsed.tags.last.name, 'raw-19');

    await expectLater(
      api.searchTopicTags(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        term: 'tag',
        categoryId: -1,
      ),
      throwsRangeError,
    );
    await expectLater(
      api.searchTopicTags(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        term: 'tag',
        limit: TopicTagSearch.maximumResults + 1,
      ),
      throwsRangeError,
    );
    expect(calls, 1, reason: 'invalid inputs must fail before transport');
  });

  test('liker and reactor requests validate their page boundary', () async {
    var calls = 0;
    final api = DiscourseApi(
      client: MockClient((request) async {
        calls++;
        return switch (request.url.path) {
          '/post_action_users.json' => http.Response(
            jsonEncode({'post_action_users': const <Object?>[]}),
            200,
          ),
          _ => http.Response(
            jsonEncode({'users': const <Object?>[], 'total_rows': 0}),
            200,
          ),
        };
      }),
    );

    await api.postLikers(
      siteUrl: 'https://example.com',
      postId: 1,
      limit: PostLikers.maximumPageSize,
    );
    await ReactionsApiClient(api, api.models).postReactors(
      siteUrl: 'https://example.com',
      postId: 1,
      limit: PostReactors.maximumPageSize,
    );
    expect(calls, 2);

    await expectLater(
      api.postLikers(siteUrl: 'https://example.com', postId: 0),
      throwsRangeError,
    );
    await expectLater(
      api.postLikers(
        siteUrl: 'https://example.com',
        postId: 1,
        limit: PostLikers.maximumPageSize + 1,
      ),
      throwsRangeError,
    );
    await expectLater(
      ReactionsApiClient(
        api,
        api.models,
      ).postReactors(siteUrl: 'https://example.com', postId: -1),
      throwsRangeError,
    );
    await expectLater(
      ReactionsApiClient(
        api,
        api.models,
      ).postReactors(siteUrl: 'https://example.com', postId: 1, limit: 0),
      throwsRangeError,
    );
    await expectLater(
      ReactionsApiClient(
        api,
        api.models,
      ).postReactors(siteUrl: 'https://example.com', postId: 1, reaction: ''),
      throwsArgumentError,
    );
    await expectLater(
      ReactionsApiClient(api, api.models).postReactors(
        siteUrl: 'https://example.com',
        postId: 1,
        reaction: 'x' * (DiscourseApi.maximumSearchTermLength + 1),
      ),
      throwsArgumentError,
    );
    expect(calls, 2, reason: 'invalid inputs must fail before transport');
  });

  test(
    'post coordinates fail locally before a read or receipt write',
    () async {
      var calls = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );

      expect(
        () => api.markNotificationRead(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          id: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => api.recordTopicRead(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          topicId: 0,
          postNumber: 1,
        ),
        throwsRangeError,
      );
      expect(
        () => api.recordTopicRead(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          topicId: 1,
          postNumber: 1,
          milliseconds: 0,
        ),
        throwsRangeError,
      );
      await expectLater(
        api.posts(siteUrl: 'https://example.com', topicId: 0, ids: const [1]),
        throwsRangeError,
      );
      await expectLater(
        api.posts(siteUrl: 'https://example.com', topicId: 1, ids: const [0]),
        throwsRangeError,
      );
      expect(
        () => api.topicPosts(
          siteUrl: 'https://example.com',
          topicId: 1,
          ids: [
            for (var id = 1; id <= TopicDetail.maximumInitialPosts + 1; id++)
              id,
          ],
        ),
        throwsRangeError,
      );
      expect(calls, 0);
    },
  );

  test(
    'hashtag and mention responses cannot exceed their request budget',
    () async {
      var calls = 0;
      final api = DiscourseApi(
        client: MockClient((request) async {
          calls++;
          if (request.url.path == '/hashtags/search.json') {
            return http.Response(
              jsonEncode({
                'results': [
                  for (var index = 0; index < 25; index++)
                    {
                      'type': 'tag',
                      'ref': 'tag-$index',
                      'slug': 'tag-$index',
                      'text': 'tag-$index',
                      'id': index + 1,
                    },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/hashtags.json') {
            return http.Response(
              jsonEncode({
                'tag': [
                  for (var index = 0; index < 25; index++)
                    {
                      'type': 'tag',
                      'ref': 'tag-$index',
                      'slug': 'tag-$index',
                      'text': 'tag-$index',
                      'id': index + 1,
                    },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'users': ['sam', 'unexpected'],
              'groups': {
                'staff': <String, dynamic>{},
                'unexpected-group': <String, dynamic>{},
              },
            }),
            200,
          );
        }),
      );

      final search = await api.searchHashtags(
        siteUrl: 'https://example.com',
        term: 'tag',
      );
      final resolved = await api.lookupHashtags(
        siteUrl: 'https://example.com',
        refs: const ['tag-0', 'tag-1'],
      );
      final mentions = await api.checkMentions(
        siteUrl: 'https://example.com',
        names: const ['sam', 'staff'],
        topicId: 1,
      );

      expect(search, hasLength(DiscourseApi.maximumAutocompleteResults));
      expect(resolved.map((value) => value.ref), ['tag-0', 'tag-1']);
      expect(mentions, {'sam', 'staff'});
      expect(calls, 3);

      expect(
        () => api.searchHashtags(
          siteUrl: 'https://example.com',
          term: 'tag',
          order: const [],
        ),
        throwsRangeError,
      );
      await expectLater(
        api.lookupHashtags(siteUrl: 'https://example.com', refs: const ['']),
        throwsArgumentError,
      );
      await expectLater(
        api.checkMentions(
          siteUrl: 'https://example.com',
          names: const ['sam'],
          topicId: 0,
        ),
        throwsRangeError,
      );
      expect(calls, 3, reason: 'invalid inputs must fail before transport');
    },
  );
}
