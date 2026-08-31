import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';

void main() {
  group('toggleReaction', () {
    Map<String, dynamic> reacted() => {
      'id': 1,
      'post_number': 1,
      'username': 'sam',
      'cooked': '<p>Hi</p>',
      'reactions': [
        {'id': 'clap', 'type': 'emoji', 'count': 1},
      ],
      'current_user_reaction': {
        'id': 'clap',
        'type': 'emoji',
        'can_undo': true,
      },
      'reaction_users_count': 1,
    };

    test('puts to the toggle route with no body at all', () async {
      late http.Request seen;
      final api = DiscourseApi(
        models: DiscourseModelCodec(
          extensions: pluginRegistry,
          recommendationSources: pluginRegistry,
          icons: pluginRegistry,
        ),
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode(reacted()), 200);
        }),
      );

      final post = await ReactionsApiClient(api, api.models).toggleReaction(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        postId: 1,
        reaction: 'clap',
      );

      expect(seen.method, 'PUT');
      expect(
        seen.url.path,
        '/discourse-reactions/posts/1/custom-reactions/clap/toggle.json',
      );
      expect(seen.body, '{}');
      expect(post?.reactions?.mine?.id, 'clap');
    });

    test('encodes a reaction that is not URL-safe', () async {
      // `+1` is a perfectly ordinary reaction id, and it is a path segment.
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode(reacted()), 200);
        }),
      );

      await ReactionsApiClient(api, api.models).toggleReaction(
        siteUrl: 'https://example.com',
        apiKey: 'k',
        postId: 1,
        reaction: '+1',
      );

      expect(seen.toString(), contains('custom-reactions/%2B1/toggle.json'));
      expect(seen.pathSegments, contains('+1'));
    });

    test('surfaces the status, so a 404 can be told from a refusal', () async {
      // A 404 means the plugin went away *or* the post did — the same bytes for
      // both — and the caller repairs one post rather than a site.
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('not found', 404)),
      );

      await expectLater(
        ReactionsApiClient(api, api.models).toggleReaction(
          siteUrl: 'https://example.com',
          apiKey: 'k',
          postId: 1,
          reaction: 'clap',
        ),
        throwsA(
          isA<WriteException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('reports a rate limit as one', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response('slow down', 429, headers: const {}),
        ),
      );

      await expectLater(
        ReactionsApiClient(api, api.models).toggleReaction(
          siteUrl: 'https://example.com',
          apiKey: 'k',
          postId: 1,
          reaction: 'clap',
        ),
        throwsA(
          isA<WriteException>().having(
            (e) => e.failure,
            'failure',
            WriteFailure.rateLimited,
          ),
        ),
      );
    });
  });

  group('postReactors', () {
    test('asks the list route and reads its envelope', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'users': [
                {'id': 3, 'username': 'sam', 'reaction': 'clap'},
              ],
              'total_rows': 4,
            }),
            200,
          );
        }),
      );

      final reactors = await ReactionsApiClient(
        api,
        api.models,
      ).postReactors(siteUrl: 'https://example.com', postId: 1);

      expect(
        seen.path,
        '/discourse-reactions/posts/1/reactions-users-list.json',
      );
      expect(seen.queryParameters['limit'], '30');
      expect(seen.queryParameters, isNot(contains('reaction_value')));
      expect(reactors.reactors.single.username, 'sam');
      expect(reactors.total, 4);
    });

    test('narrows to one emoji when asked to', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({'users': const <Object?>[], 'total_rows': 0}),
            200,
          );
        }),
      );

      final reactors = await ReactionsApiClient(
        api,
        api.models,
      ).postReactors(siteUrl: 'https://example.com', postId: 1, reaction: '+1');

      expect(seen.queryParameters['reaction_value'], '+1');
      expect(reactors.filter, '+1');
    });
  });

  group('chatDirectMessages', () {
    test('searches core Chat’s permission-filtered DM targets', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'identifier': 'u-2',
                  'type': 'user',
                  'match_quality': 1,
                  'model': {
                    'id': 2,
                    'username': 'sam',
                    'name': 'Sam',
                    'avatar_template':
                        '/user_avatar/example.com/sam/{size}/1.png',
                    'has_chat_enabled': true,
                  },
                },
              ],
              'groups': [
                {
                  'identifier': 'g-8',
                  'type': 'group',
                  'match_quality': 2,
                  'model': {
                    'id': 8,
                    'name': 'sam-fans',
                    'full_name': 'Sam fans',
                    'can_chat': true,
                    'chat_enabled_user_count': 4,
                  },
                },
              ],
              'direct_message_channels': [
                {
                  'identifier': 'c-55',
                  'type': 'channel',
                  'match_quality': 2,
                  'model': {
                    'id': 55,
                    'title': 'Sam and Kris',
                    'chatable_type': 'DirectMessage',
                    'chatable': {'group': true, 'users': const <Object?>[]},
                  },
                },
              ],
              'category_channels': const <Object?>[],
            }),
            200,
          );
        }),
      );

      final results = await ChatApiClient(api).searchChatDirectMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
        term: 'sam',
        includeGroups: true,
      );

      expect(seen.url.path, '/chat/api/chatables');
      expect(seen.url.queryParameters, {
        'term': 'sam',
        'include_users': 'true',
        'include_groups': 'true',
        'include_category_channels': 'false',
        'include_direct_message_channels': 'true',
      });
      expect(results.items, hasLength(3));
      expect(results.items.first, isA<ChatDirectMessageUser>());
      expect((results.items.first as ChatDirectMessageUser).username, 'sam');
      expect((results.items[1] as ChatDirectMessageChannel).channel.id, 55);
      expect((results.items.last as ChatDirectMessageGroup).name, 'sam-fans');
    });

    test('upserts a DM channel for the user-card Chat action', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 55,
                'title': 'sam',
                'chatable_type': 'DirectMessage',
                'chatable': {
                  'group': false,
                  'users': [
                    {'id': 2, 'username': 'sam'},
                  ],
                },
              },
            }),
            200,
          );
        }),
      );

      final channel = await ChatApiClient(api).createChatDirectMessageChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
        usernames: const ['sam'],
        upsert: true,
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/chat/api/direct-message-channels.json');
      expect(jsonDecode(seen.body), {
        'target_usernames': ['sam'],
        'upsert': true,
      });
      expect(channel.id, 55);
      expect(channel.isDirectMessage, isTrue);
    });

    test('creates a named group DM from users and visible groups', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 56,
                'title': 'Triage',
                'chatable_type': 'DirectMessage',
                'chatable': {'group': true, 'users': const <Object?>[]},
              },
            }),
            200,
          );
        }),
      );

      final channel = await ChatApiClient(api).createChatDirectMessageChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
        usernames: const ['sam', 'kris'],
        groups: const ['moderators'],
        name: 'Triage',
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/chat/api/direct-message-channels.json');
      expect(jsonDecode(seen.body), {
        'target_usernames': ['sam', 'kris'],
        'target_groups': ['moderators'],
        'upsert': false,
        'name': 'Triage',
      });
      expect(channel.id, 56);
      expect(channel.isGroup, isTrue);
    });
  });

  group('chatChannels', () {
    MockClient serving(void Function(http.Request) record) => MockClient((
      request,
    ) async {
      record(request);
      return http.Response(
        jsonEncode({
          'public_channels': [
            {
              'id': 9,
              'title': 'Bugs',
              'slug': 'bugs',
              'chatable_type': 'Category',
              'chatable': {'name': 'Bug', 'color': '0088CC'},
              'current_user_membership': {'following': true, 'starred': true},
            },
          ],
          'direct_message_channels': [
            {
              'id': 12,
              'title': 'hawk',
              'chatable_type': 'DirectMessage',
              'chatable': {
                'group': false,
                'users': [
                  {'id': 2, 'username': 'hawk'},
                ],
              },
            },
          ],
          'tracking': {
            'channel_tracking': {
              '9': {'unread_count': 3, 'mention_count': 1},
            },
          },
          'meta': {'message_bus_last_ids': <String, dynamic>{}},
        }),
        200,
      );
    });

    test(
      'asks the route that answers with only the channels a reader follows',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await ChatApiClient(api).chatChannels(siteUrl: 'https://example.com');

        expect(seen.path, '/chat/api/me/channels.json');
        // The route takes no parameters at all — the reader's own memberships are
        // the whole of the query.
        expect(seen.queryParameters, isEmpty);
      },
    );

    test('reads the public and the direct lists apart', () async {
      final api = DiscourseApi(client: serving((_) {}));

      final channels = await ChatApiClient(
        api,
      ).chatChannels(siteUrl: 'https://example.com');

      expect(channels.public.single.title, 'Bugs');
      expect(channels.direct.single.isDirectMessage, isTrue);
      expect(channels.public.single.tracking.unreadCount, 3);
      expect(channels.public.single.membership.starred, isTrue);
    });

    test(
      'sends the user API key, an anonymous reader having no channels',
      () async {
        late Map<String, String> headers;
        final api = DiscourseApi(client: serving((r) => headers = r.headers));

        await ChatApiClient(api).chatChannels(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          clientId: 'client',
        );

        expect(headers['User-Api-Key'], 'key');
        expect(headers['User-Api-Client-Id'], 'client');
      },
    );

    test('updates the current channel membership starred setting', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).updateChatChannelStarred(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        starred: true,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9/memberships/me.json');
      expect(jsonDecode(sent.body), {'starred': true});
    });

    test('updates independent channel notification settings', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'membership': {
                'following': true,
                'muted': true,
                'notification_level': 'always',
                'starred': true,
                'last_read_message_id': 44,
              },
            }),
            200,
          );
        }),
      );

      final membership = await ChatApiClient(api)
          .updateChatChannelNotifications(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            channelId: 9,
            muted: true,
            notificationLevel: ChatChannelNotificationLevel.always,
          );

      expect(sent.method, 'PUT');
      expect(
        sent.url.path,
        '/chat/api/channels/9/notifications-settings/me.json',
      );
      expect(jsonDecode(sent.body), {
        'notifications_settings': {
          'muted': true,
          'notification_level': 'always',
        },
      });
      expect(membership.muted, isTrue);
      expect(membership.notificationLevel, ChatChannelNotificationLevel.always);
      expect(membership.starred, isTrue);
      expect(membership.lastReadMessageId, 44);
    });

    test('sends only the channel notification field being changed', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'membership': {
                'following': true,
                'muted': false,
                'notification_level': 'mention',
              },
            }),
            200,
          );
        }),
      );

      await ChatApiClient(api).updateChatChannelNotifications(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        muted: false,
      );

      expect(jsonDecode(sent.body), {
        'notifications_settings': {'muted': false},
      });
    });

    test('lists a filtered page of channel members', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'memberships': [
                {
                  'user': {
                    'id': 2,
                    'username': 'sam',
                    'name': 'Sam',
                    'avatar_template': '/user_avatar/sam/{size}.png',
                  },
                },
                {
                  'user': {
                    'id': 3,
                    'username': 'samantha',
                    'avatar_template': '/user_avatar/samantha/{size}.png',
                  },
                },
                {'user': null},
              ],
              'meta': {'total_rows': 42, 'load_more_url': '/next'},
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatChannelMembers(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        username: ' sam ',
        offset: 20,
        limit: 2,
      );

      expect(sent.method, 'GET');
      expect(sent.url.path, '/chat/api/channels/9/memberships');
      expect(sent.url.queryParameters, {
        'offset': '20',
        'limit': '2',
        'username': 'sam',
      });
      expect(page.members.map((member) => member.username), [
        'sam',
        'samantha',
      ]);
      expect(page.members.first.avatarUrl, contains('/user_avatar/sam/90.png'));
      expect(page.totalRows, 42);
      expect(page.canLoadMore, isTrue);
    });

    test('browses a filtered page of public channels', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channels': [
                {
                  'id': 9,
                  'title': 'Bugs',
                  'slug': 'bugs',
                  'chatable_type': 'Category',
                  'chatable': {'color': '0088CC'},
                  'memberships_count': 42,
                  'meta': {'can_join_chat_channel': true},
                },
              ],
              'meta': {'load_more_url': '/chat/api/channels?offset=25'},
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).browseChatChannels(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        filter: ' bugs ',
        status: ChatChannelBrowseStatus.open,
        offset: 25,
        limit: 1,
      );

      expect(sent.method, 'GET');
      expect(sent.url.path, '/chat/api/channels');
      expect(sent.url.queryParameters, {
        'status': 'open',
        'offset': '25',
        'limit': '1',
        'filter': 'bugs',
      });
      expect(page.channels.single.title, 'Bugs');
      expect(page.channels.single.membershipsCount, 42);
      expect(page.channels.single.canJoin, isTrue);
      expect(page.hasMore, isTrue);
    });

    test('joins and reversibly unfollows channel memberships', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(
            jsonEncode({
              'membership': {
                'following': request.method == 'POST',
                'notification_level': 'mention',
              },
            }),
            200,
          );
        }),
      );

      final joined = await ChatApiClient(api).followChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );
      final unfollowed = await ChatApiClient(api).unfollowChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );

      expect(sent[0].method, 'POST');
      expect(sent[0].url.path, '/chat/api/channels/9/memberships/me.json');
      expect(jsonDecode(sent[0].body), isEmpty);
      expect(joined.following, isTrue);
      expect(sent[1].method, 'DELETE');
      expect(
        sent[1].url.path,
        '/chat/api/channels/9/memberships/me/follows.json',
      );
      expect(jsonDecode(sent[1].body), isEmpty);
      expect(unfollowed.following, isFalse);
    });

    test('edits a chat message and retains its uploads', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).editChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
        message: '**corrected**',
        uploadIds: const [31, 32],
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9/messages/12.json');
      expect(jsonDecode(sent.body), {
        'message': '**corrected**',
        'upload_ids': [31, 32],
      });
    });

    test('deletes and restores a chat message on core routes', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).deleteChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
      );
      await ChatApiClient(api).restoreChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
      );

      expect(sent.map((request) => request.method), ['DELETE', 'PUT']);
      expect(sent.map((request) => request.url.path), [
        '/chat/api/channels/9/messages/12.json',
        '/chat/api/channels/9/messages/12/restore.json',
      ]);
      expect(sent.map((request) => jsonDecode(request.body)), [
        <String, dynamic>{},
        <String, dynamic>{},
      ]);
    });

    test('bulk-deletes selected chat messages on the core route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).deleteChatMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageIds: const [12, 14],
      );

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/chat/api/channels/9/messages.json');
      expect(jsonDecode(sent.body), {
        'message_ids': [12, 14],
      });
    });

    test('moves selected messages between public channels', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'success': 'OK',
              'destination_channel_id': 10,
              'destination_channel_title': 'Support',
              'first_moved_message_id': 101,
            }),
            200,
          );
        }),
      );

      final moved = await ChatApiClient(api).moveChatMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        destinationChannelId: 10,
        messageIds: const [12, 14],
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/chat/api/channels/9/messages/moves.json');
      expect(jsonDecode(sent.body), {
        'move': {
          'message_ids': [12, 14],
          'destination_channel_id': 10,
        },
      });
      expect(moved.destinationChannelId, 10);
      expect(moved.firstMovedMessageId, 101);
    });

    test('queues a chat message HTML rebuild on the core route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).rebakeChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/9/12/rebake.json');
      expect(jsonDecode(sent.body), <String, dynamic>{});
    });

    test('generates canonical Markdown for selected chat messages', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({'markdown': '[chat channel="Bugs"]\nHello\n[/chat]'}),
            200,
          );
        }),
      );

      final markdown = await ChatApiClient(api).generateChatQuote(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageIds: const [12, 14],
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/chat/9/quote.json');
      expect(jsonDecode(sent.body), {
        'message_ids': [12, 14],
      });
      expect(markdown, '[chat channel="Bugs"]\nHello\n[/chat]');
    });

    test('pins and unpins a chat message with core route methods', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).updateChatMessagePinned(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
        pinned: true,
      );
      await ChatApiClient(api).updateChatMessagePinned(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
        pinned: false,
      );

      expect(sent.map((request) => request.method), ['POST', 'DELETE']);
      expect(sent.map((request) => request.url.path), [
        '/chat/api/channels/9/messages/12/pin.json',
        '/chat/api/channels/9/messages/12/pin.json',
      ]);
      expect(sent.map((request) => jsonDecode(request.body)), [
        <String, dynamic>{},
        <String, dynamic>{},
      ]);
    });

    test('loads pinned messages and marks their panel read', () async {
      final sent = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'pinned_messages': [
                  {
                    'id': 91,
                    'chat_message_id': 12,
                    'message': {
                      'id': 12,
                      'chat_channel_id': 9,
                      'cooked': '<p>Pin</p>',
                      'user': {'id': 2, 'username': 'sam'},
                    },
                    'pinned_by': {'id': 7, 'username': 'reader'},
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      final snapshot = await ChatApiClient(api).chatPinnedMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );
      await ChatApiClient(api).markChatPinsRead(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );

      expect(snapshot.pins.single.messageId, 12);
      expect(sent.map((request) => request.method), ['GET', 'PUT']);
      expect(sent.map((request) => request.url.path), [
        '/chat/api/channels/9/pins.json',
        '/chat/api/channels/9/pins/read.json',
      ]);
      expect(jsonDecode(sent.last.body), <String, dynamic>{});
    });

    test('flags a chat message with its server-advertised reason', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).flagChatMessage(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        messageId: 12,
        flagTypeId: 7,
        message: 'Please review this message.',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/chat/api/channels/9/messages/12/flags.json');
      expect(jsonDecode(sent.body), {
        'flag_type_id': 7,
        'message': 'Please review this message.',
      });
    });

    test('reports a site that refuses the way every other read does', () async {
      // 403 is what a site with chat off, or a reader who may not use it, gets.
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('{}', 403)),
      );

      await expectLater(
        ChatApiClient(api).chatChannels(siteUrl: 'https://example.com'),
        throwsA(isA<SiteLookupException>()),
      );
    });
  });

  group('chatSearch', () {
    Map<String, dynamic> message(int id) => {
      'id': id,
      'chat_channel_id': 9,
      'cooked': '<p>needle</p>',
      'excerpt': 'needle',
      'created_at': '2026-08-25T10:00:00Z',
      'user': {'id': 2, 'username': 'sam'},
      'channel': {
        'id': 9,
        'title': 'Bugs',
        'chatable_type': 'Category',
        'chatable': {'color': '0088CC'},
      },
    };

    test('sends global search paging and sorting parameters', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'messages': [message(40)],
              'meta': {'has_more': true, 'limit': 20, 'offset': 20},
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).searchChatMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        clientId: 'client',
        query: '  needle  ',
        sort: ChatSearchSort.latest,
        offset: 20,
      );

      expect(seen.url.path, '/chat/api/search.json');
      expect(seen.url.queryParameters, {
        'query': 'needle',
        'sort': 'latest',
        'offset': '20',
        'limit': '20',
      });
      expect(seen.headers['User-Api-Key'], 'key');
      expect(page.hits.single.id, 40);
      expect(page.hasMore, isTrue);
    });

    test('scopes channel search and excludes thread replies', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({'messages': const <Object?>[]}),
            200,
          );
        }),
      );

      await ChatApiClient(api).searchChatMessages(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        query: 'needle',
        channelId: 9,
        sort: ChatSearchSort.latest,
        excludeThreads: true,
      );

      expect(seen.queryParameters['channel_id'], '9');
      expect(seen.queryParameters['exclude_threads'], 'true');
    });

    test('rejects invalid search values before sending', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      final calls = <Future<void> Function()>[
        () => ChatApiClient(api).searchChatMessages(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          query: ' ',
        ),
        () => ChatApiClient(api).searchChatMessages(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          query: 'needle',
          channelId: 0,
        ),
        () => ChatApiClient(api).searchChatMessages(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          query: 'needle',
          offset: -1,
        ),
        () => ChatApiClient(api).searchChatMessages(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          query: 'needle',
          limit: 41,
        ),
      ];
      for (final call in calls) {
        await expectLater(call(), throwsArgumentError);
      }
      expect(requests, 0);
    });

    test('loads one full channel for result navigation', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bugs',
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
                'current_user_membership': {'following': true},
              },
            }),
            200,
          );
        }),
      );

      final channel = await ChatApiClient(api).chatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
      );

      expect(seen.path, '/chat/api/channels/9.json');
      expect(channel.membership.following, isTrue);
    });
  });

  group('chat channel management', () {
    test('updates channel metadata in core’s channel envelope', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bug reports',
                'slug': 'bug-reports',
                'description': 'A better description.',
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
                'current_user_membership': {'following': true},
              },
            }),
            200,
          );
        }),
      );

      final updated = await ChatApiClient(api).updateChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        name: '  Bug reports  ',
        slug: '  bug-reports  ',
        description: 'A better description.',
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9.json');
      expect(jsonDecode(sent.body), {
        'channel': {
          'name': 'Bug reports',
          'slug': 'bug-reports',
          'description': 'A better description.',
        },
      });
      expect(updated.title, 'Bug reports');
      expect(updated.description, 'A better description.');
    });

    test('sends an empty description so core removes it', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bugs',
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
                'current_user_membership': {'following': true},
              },
            }),
            200,
          );
        }),
      );

      await ChatApiClient(api).updateChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        description: '',
      );

      expect(jsonDecode(sent.body), {
        'channel': {'description': ''},
      });
    });

    test('toggles channel threading through the same settings route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bugs',
                'threading_enabled': true,
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
                'current_user_membership': {'following': true},
              },
            }),
            200,
          );
        }),
      );

      final updated = await ChatApiClient(api).updateChatChannel(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        threadingEnabled: true,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9.json');
      expect(jsonDecode(sent.body), {
        'channel': {'threading_enabled': true},
      });
      expect(updated.threadingEnabled, isTrue);
    });

    test('closes a channel through core’s dedicated status route', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'channel': {
                'id': 9,
                'title': 'Bugs',
                'status': 'closed',
                'chatable_type': 'Category',
                'chatable': {'color': '0088CC'},
              },
            }),
            200,
          );
        }),
      );

      final updated = await ChatApiClient(api).updateChatChannelStatus(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        status: ChatChannelStatus.closed,
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/chat/api/channels/9/status.json');
      expect(jsonDecode(sent.body), {'status': 'closed'});
      expect(updated.status, ChatChannelStatus.closed);
    });

    test('rejects archive states from the open-close route', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        ChatApiClient(api).updateChatChannelStatus(
          siteUrl: 'https://example.com',
          apiKey: 'key',
          channelId: 9,
          status: ChatChannelStatus.archived,
        ),
        throwsArgumentError,
      );
    });
  });

  group('chatMessages', () {
    MockClient serving(
      void Function(http.Request) record, {
      Object? canLoadMorePast,
    }) => MockClient((request) async {
      record(request);
      return http.Response(
        jsonEncode({
          'messages': [
            {
              'id': 40,
              'chat_channel_id': 9,
              'cooked': '<p>hi</p>',
              'created_at': '2026-05-05T10:00:00.000Z',
              'user': {'id': 2, 'username': 'sam'},
            },
          ],
          'meta': {
            'can_load_more_past': canLoadMorePast,
            'can_load_more_future': null,
          },
        }),
        200,
      );
    });

    test('asks for the newest page when no message is named', () async {
      late Uri seen;
      final api = DiscourseApi(client: serving((r) => seen = r.url));

      final page = await ChatApiClient(
        api,
      ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

      expect(seen.path, '/chat/api/channels/9/messages.json');
      expect(seen.queryParameters['page_size'], '50');
      expect(page.messages.single.id, 40);
    });

    test('rejects invalid pagination before sending a request', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );
      final invalidCalls = <Future<void> Function()>[
        () => ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 1,
          after: 2,
        ),
        () => ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 1,
          fromLastRead: true,
        ),
        () => ChatApiClient(
          api,
        ).chatMessages(siteUrl: 'https://example.com', channelId: 0),
        () => ChatApiClient(
          api,
        ).chatMessages(siteUrl: 'https://example.com', channelId: 9, before: 0),
        () => ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          pageSize: 0,
        ),
        () => ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          pageSize: 51,
        ),
      ];

      for (final call in invalidCalls) {
        await expectLater(call(), throwsArgumentError);
      }
      expect(requests, 0);
    });

    test('omits the target message rather than sending an empty one', () async {
      // `target_message_id=` reads as 0 server side and 404s for a message
      // that cannot exist.
      late Uri seen;
      final api = DiscourseApi(client: serving((r) => seen = r.url));

      await ChatApiClient(
        api,
      ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

      expect(seen.queryParameters, isNot(contains('target_message_id')));
      expect(seen.queryParameters, isNot(contains('direction')));
    });

    test(
      'asks for the page before a message it holds, that message excluded',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          before: 40,
        );

        expect(seen.queryParameters['direction'], 'past');
        expect(seen.queryParameters['target_message_id'], '40');
      },
    );

    test('asks for a directionless page around an explicit message', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'messages': <Object?>[],
              'meta': {
                'target_message_id': 40,
                'can_load_more_past': true,
                'can_load_more_future': true,
              },
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatMessages(
        siteUrl: 'https://example.com',
        channelId: 9,
        targetMessageId: 40,
        pageSize: 20,
      );

      expect(seen.queryParameters['target_message_id'], '40');
      expect(seen.queryParameters['page_size'], '20');
      expect(seen.queryParameters, isNot(contains('direction')));
      expect(page.targetMessageId, 40);
    });

    test(
      'never asks to fetch from last read, there being no way to page forward',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await ChatApiClient(
          api,
        ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

        expect(seen.queryParameters, isNot(contains('fetch_from_last_read')));
      },
    );

    test(
      'sends the page size the site caps at, so the code names the real one',
      () async {
        late Uri seen;
        final api = DiscourseApi(client: serving((r) => seen = r.url));

        await ChatApiClient(api).chatMessages(
          siteUrl: 'https://example.com',
          channelId: 9,
          pageSize: 20,
        );

        expect(seen.queryParameters['page_size'], '20');
      },
    );

    test(
      'reads a null can_load_more_past as no more rather than as unknown',
      () async {
        // Ruby leaves the flag for the direction it did not paginate unassigned.
        final api = DiscourseApi(
          client: serving((_) {}, canLoadMorePast: null),
        );

        final page = await ChatApiClient(
          api,
        ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

        expect(page.canLoadMorePast, isFalse);
      },
    );

    test('reads a channel that says there is more behind it', () async {
      final api = DiscourseApi(client: serving((_) {}, canLoadMorePast: true));

      final page = await ChatApiClient(
        api,
      ).chatMessages(siteUrl: 'https://example.com', channelId: 9);

      expect(page.canLoadMorePast, isTrue);
    });
  });

  group('chatThreadMessages', () {
    test('requests an explicit target and bounded page size', () async {
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'messages': <Object?>[],
              'meta': {
                'target_message_id': 44,
                'can_load_more_past': true,
                'can_load_more_future': true,
              },
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatThreadMessages(
        siteUrl: 'https://example.com',
        channelId: 9,
        threadId: 22,
        targetMessageId: 44,
        pageSize: 20,
      );

      expect(seen.path, '/chat/api/channels/9/threads/22/messages.json');
      expect(seen.queryParameters['target_message_id'], '44');
      expect(seen.queryParameters['page_size'], '20');
      expect(seen.queryParameters, isNot(contains('direction')));
      expect(page.targetMessageId, 44);
    });

    test('rejects invalid identities and direction before transport', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests += 1;
          return http.Response('{}', 200);
        }),
      );
      final invalidCalls = <Future<void> Function()>[
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 0,
          threadId: 2,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 0,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          before: 3,
          after: 4,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          after: -1,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          targetMessageId: 3,
          before: 4,
        ),
        () => ChatApiClient(api).chatThreadMessages(
          siteUrl: 'https://example.com',
          channelId: 1,
          threadId: 2,
          pageSize: 51,
        ),
      ];

      for (final call in invalidCalls) {
        await expectLater(call(), throwsArgumentError);
      }
      expect(requests, 0);
    });
  });

  group('chat thread detail and settings', () {
    Map<String, dynamic> serializedThread({bool membership = true}) => {
      'id': 22,
      'channel_id': 9,
      'status': 'open',
      'reply_count': 4,
      'last_message_id': 108,
      'force': false,
      'meta': {
        'message_bus_last_ids': {'thread_message_bus_last_id': 456},
      },
      if (membership)
        'current_user_membership': {
          'thread_id': 22,
          'notification_level': 2,
          'last_read_message_id': 105,
          'thread_title_prompt_seen': false,
        },
      'original_message': {
        'id': 100,
        'chat_channel_id': 9,
        'message': 'Deploy?',
        'cooked': '<p>Deploy?</p>',
        'excerpt': 'Deploy?',
        'user': {'id': 2, 'username': 'sam'},
      },
      'preview': {
        'last_reply_id': 108,
        'last_reply_user': {'id': 3, 'username': 'lee'},
        'participant_count': 2,
        'participant_users': [
          {'id': 2, 'username': 'sam'},
          {'id': 3, 'username': 'lee'},
        ],
      },
    };

    test('fetches rooted thread detail', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'thread': serializedThread()}), 200);
        }),
      );

      final thread = await ChatApiClient(api).chatThread(
        siteUrl: 'https://example.com',
        channelId: 9,
        threadId: 22,
        apiKey: 'key',
      );

      expect(seen.method, 'GET');
      expect(seen.url.path, '/chat/api/channels/9/threads/22.json');
      expect(thread.messageBusLastId, 456);
      expect(thread.membership?.lastReadMessageId, 105);
      expect(thread.originalMessage?.id, 100);
      expect(thread.preview?.lastReplyId, 108);
    });

    test('fetches one account thread page with core pagination', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'meta': {
                'load_more_url': '/chat/api/me/threads?limit=10&offset=20',
              },
              'tracking': {
                '22': {'unread_count': 2},
              },
              'threads': [
                {
                  ...serializedThread(),
                  'channel': {
                    'id': 9,
                    'title': 'Support',
                    'chatable_type': 'Category',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(
        api,
      ).chatThreads(siteUrl: 'https://example.com', apiKey: 'key', offset: 10);

      expect(seen.method, 'GET');
      expect(seen.url.path, '/chat/api/me/threads.json');
      expect(seen.url.queryParameters, {'limit': '10', 'offset': '10'});
      expect(page.threads.single.tracking.unreadCount, 2);
      expect(page.channels.single.title, 'Support');
      expect(page.hasMore, isTrue);
    });

    test('fetches one channel thread page with core pagination', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'meta': {
                'load_more_url':
                    '/chat/api/channels/9/threads?limit=10&offset=20',
              },
              'tracking': {
                '22': {'watched_threads_unread_count': 1},
              },
              'threads': [serializedThread()],
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatChannelThreads(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        offset: 10,
      );

      expect(seen.method, 'GET');
      expect(seen.url.path, '/chat/api/channels/9/threads.json');
      expect(seen.url.queryParameters, {'limit': '10', 'offset': '10'});
      expect(page.threads.single.tracking.watchedThreadsUnreadCount, 1);
      expect(page.hasMore, isTrue);
    });

    test('creates an unrooted thread from an original message', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode(serializedThread(membership: false)),
            200,
          );
        }),
      );

      final thread = await ChatApiClient(api).createChatThread(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        originalMessageId: 100,
        title: 'Deploy plan',
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/chat/api/channels/9/threads.json');
      expect(jsonDecode(seen.body), {
        'original_message_id': 100,
        'title': 'Deploy plan',
      });
      expect(thread.id, 22);
      expect(thread.membership, isNull);
    });

    test('updates and returns the current thread membership', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'membership': {
                'thread_id': 22,
                'notification_level': 3,
                'last_read_message_id': 105,
                'thread_title_prompt_seen': false,
              },
            }),
            200,
          );
        }),
      );

      final membership = await ChatApiClient(api)
          .updateChatThreadNotificationLevel(
            siteUrl: 'https://example.com',
            apiKey: 'key',
            channelId: 9,
            threadId: 22,
            notificationLevel: ChatThreadNotificationLevel.watching,
          );

      expect(seen.method, 'PUT');
      expect(
        seen.url.path,
        '/chat/api/channels/9/threads/22/notifications-settings/me.json',
      );
      expect(jsonDecode(seen.body), {'notification_level': 3});
      expect(
        membership.notificationLevel,
        ChatThreadNotificationLevel.watching,
      );
    });

    test('updates a thread title through the core thread route', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).updateChatThreadTitle(
        siteUrl: 'https://example.com',
        apiKey: 'key',
        channelId: 9,
        threadId: 22,
        title: 'Deploy plan',
      );

      expect(seen.method, 'PUT');
      expect(seen.url.path, '/chat/api/channels/9/threads/22.json');
      expect(jsonDecode(seen.body), {'title': 'Deploy plan'});
    });
  });

  group('markChatChannelRead', () {
    test('names the message the reader has got to, in the query', () async {
      String? method;
      late Uri seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          method = request.method;
          seen = request.url;
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).markChatChannelRead(
        siteUrl: 'https://example.com',
        apiKey: 'the-key',
        channelId: 9,
        messageId: 44,
      );

      expect(method, 'PUT');
      expect(seen.path, '/chat/api/channels/9/read.json');
      expect(seen.queryParameters['message_id'], '44');
    });

    test('reports a refusal rather than swallowing it', () async {
      final api = DiscourseApi(
        client: MockClient((_) async => http.Response('', 404)),
      );

      await expectLater(
        ChatApiClient(api).markChatChannelRead(
          siteUrl: 'https://example.com',
          apiKey: 'the-key',
          channelId: 9,
          messageId: 44,
        ),
        throwsA(isA<WriteException>()),
      );
    });
  });

  group('setChatMessageReaction', () {
    test('puts the explicit add or remove action on the chat route', () async {
      final requests = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'success': 'OK'}), 200);
        }),
      );

      await ChatApiClient(api).setChatMessageReaction(
        siteUrl: 'https://example.com',
        apiKey: 'the-key',
        channelId: 9,
        messageId: 44,
        emoji: '+1',
        action: ChatReactionAction.add,
      );
      await ChatApiClient(api).setChatMessageReaction(
        siteUrl: 'https://example.com',
        apiKey: 'the-key',
        channelId: 9,
        messageId: 44,
        emoji: '+1',
        action: ChatReactionAction.remove,
      );

      expect(requests.map((request) => request.method), everyElement('PUT'));
      expect(
        requests.map((request) => request.url.path),
        everyElement('/chat/9/react/44.json'),
      );
      expect(jsonDecode(requests.first.body), {
        'emoji': '+1',
        'react_action': 'add',
      });
      expect(jsonDecode(requests.last.body), {
        'emoji': '+1',
        'react_action': 'remove',
      });
    });

    test('rejects invalid identities and emoji before transport', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      Future<void> react(int channelId, int messageId, String emoji) =>
          ChatApiClient(api).setChatMessageReaction(
            siteUrl: 'https://example.com',
            apiKey: 'the-key',
            channelId: channelId,
            messageId: messageId,
            emoji: emoji,
            action: ChatReactionAction.add,
          );

      await expectLater(react(0, 44, 'heart'), throwsArgumentError);
      await expectLater(react(9, 0, 'heart'), throwsArgumentError);
      await expectLater(react(9, 44, ''), throwsArgumentError);
      expect(requests, 0);
    });

    test('maps a server refusal to the shared write failure', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'errors': ['You cannot react right now.'],
            }),
            403,
          ),
        ),
      );

      await expectLater(
        ChatApiClient(api).setChatMessageReaction(
          siteUrl: 'https://example.com',
          apiKey: 'the-key',
          channelId: 9,
          messageId: 44,
          emoji: 'heart',
          action: ChatReactionAction.add,
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.message,
            'message',
            contains('cannot react'),
          ),
        ),
      );
    });
  });

  group('chatMessageReactors', () {
    test('asks chat for one emoji and reads its users', () async {
      late http.Request seen;
      final api = DiscourseApi(
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'users': [
                {
                  'id': 3,
                  'username': 'sam',
                  'name': 'Sam Saffron',
                  'reaction': 'clap',
                },
              ],
              'total_rows': 2,
            }),
            200,
          );
        }),
      );

      final page = await ChatApiClient(api).chatMessageReactors(
        siteUrl: 'https://example.com',
        apiKey: 'the-key',
        channelId: 9,
        messageId: 44,
        reaction: '+1',
      );

      expect(seen.method, 'GET');
      expect(seen.url.path, '/chat/9/44/reactions-users.json');
      expect(seen.url.queryParameters, {
        'page': '0',
        'limit': '${ChatMessageReactors.maximumPageSize}',
        'emoji': '+1',
      });
      expect(page.channelId, 9);
      expect(page.messageId, 44);
      expect(page.filter, '+1');
      expect(page.total, 2);
      expect(page.reactors.single.displayName, 'Sam Saffron');
    });

    test('rejects invalid identities, filters and page sizes', () async {
      var requests = 0;
      final api = DiscourseApi(
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      Future<void> load({
        int channelId = 9,
        int messageId = 44,
        String? reaction,
        int limit = ChatMessageReactors.maximumPageSize,
      }) async {
        await ChatApiClient(api).chatMessageReactors(
          siteUrl: 'https://example.com',
          apiKey: 'the-key',
          channelId: channelId,
          messageId: messageId,
          reaction: reaction,
          limit: limit,
        );
      }

      await expectLater(load(channelId: 0), throwsArgumentError);
      await expectLater(load(messageId: 0), throwsArgumentError);
      await expectLater(load(reaction: ''), throwsArgumentError);
      await expectLater(load(limit: 0), throwsRangeError);
      await expectLater(
        load(limit: ChatMessageReactors.maximumPageSize + 1),
        throwsRangeError,
      );
      expect(requests, 0);
    });
  });
}
