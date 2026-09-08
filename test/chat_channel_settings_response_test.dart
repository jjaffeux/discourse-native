import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
final _original = ChatChannel(
  id: 9,
  title: 'Bugs',
  slug: 'bugs',
  description: 'Original description',
  kind: ChatChannelKind.category,
  membershipsCount: 3,
  membership: const ChatMembership(
    following: true,
    starred: true,
    lastReadMessageId: 10,
  ),
  tracking: const ChatTracking(unreadCount: 2, mentionCount: 1),
  lastMessageId: 12,
  lastMessageAt: DateTime.utc(2026, 9, 8, 10),
);

void main() {
  group('channel settings response ownership', () {
    test(
      'a description response preserves a live close and activity',
      () async {
        final fixture = _Fixture();
        await fixture.load();

        final writing = fixture.chat.updateChannelMetadata(
          _site,
          9,
          description: 'Saved description',
        );
        await fixture.metadataStarted();
        fixture.statusEvent('closed');
        fixture.activityEvents();
        final live = fixture.channel;
        expect(live.status, ChatChannelStatus.closed);

        fixture.metadataGate.complete();
        expect(await writing, isNull);
        expect(fixture.channel.status, ChatChannelStatus.closed);
        expect(
          fixture.channel,
          live.withRemoteMetadata(
            title: live.title,
            slug: live.slug!,
            description: 'Saved description',
          ),
        );
        expect(fixture.chat.channelSettingsWriteInFlight(_site, 9), isFalse);
        expect(fixture.api.chatChannelsRequested, [_site]);
        expect(fixture.api.chatChannelDetailsRequested, isEmpty);
      },
    );

    test('a status response preserves a live rename and activity', () async {
      final fixture = _Fixture();
      await fixture.load();

      final writing = fixture.chat.setChannelClosed(_site, 9, closed: true);
      await fixture.statusStarted();
      fixture.editEvent('Support', 'support', 'Ask for help');
      fixture.activityEvents();
      final live = fixture.channel;
      expect(live.title, 'Support');

      fixture.statusGate.complete();
      expect(await writing, isNull);
      expect(fixture.channel.title, 'Support');
      expect(fixture.channel, live.withRemoteStatus(ChatChannelStatus.closed));
      expect(fixture.chat.channelSettingsWriteInFlight(_site, 9), isFalse);
      expect(fixture.api.chatChannelsRequested, [_site]);
      expect(fixture.api.chatChannelDetailsRequested, isEmpty);
    });

    test('a live reopen supersedes the delayed close response', () async {
      final fixture = _Fixture();
      await fixture.load();

      final writing = fixture.chat.setChannelClosed(_site, 9, closed: true);
      await fixture.statusStarted();
      // The write's own event arrives, then another staff member reopens it.
      fixture.statusEvent('closed');
      fixture.statusEvent('open');
      final live = fixture.channel;
      expect(live.status, ChatChannelStatus.open);

      fixture.statusGate.complete();
      expect(await writing, isNull);
      expect(fixture.channel.status, ChatChannelStatus.open);
      expect(fixture.channel, live);
    });

    test(
      'live text edits supersede a response without claiming threading',
      () async {
        final response = _original
            .withRemoteMetadata(
              title: 'Support',
              slug: 'support',
              description: 'Saved description',
            )
            .withThreadingEnabled(true);
        final fixture = _Fixture(metadataResponse: response);
        await fixture.load();

        final writing = fixture.chat.updateChannelMetadata(
          _site,
          9,
          name: 'Support',
          slug: 'support',
          description: 'Saved description',
          threadingEnabled: true,
        );
        await fixture.metadataStarted();
        fixture.editEvent('Support', 'support', 'Saved description');
        // Another staff member restores the original text before PUT completes.
        fixture.editEvent(
          _original.title,
          _original.slug!,
          _original.description,
        );
        fixture.statusEvent('closed');
        final live = fixture.channel;

        fixture.metadataGate.complete();
        expect(await writing, isNull);
        expect(fixture.channel, live.withThreadingEnabled(true));
        expect(fixture.channel.title, _original.title);
      },
    );

    test(
      'the write’s own live edit accepts canonical Unicode title normalization',
      () async {
        final response = ChatChannel.fromJson(const {
          'id': 9,
          'chatable_type': 'Category',
          'title': 'Bugs :bug:',
          'unicode_title': 'Bugs 🐛',
          'slug': 'bugs',
        }, _site);
        final fixture = _Fixture(metadataResponse: response);
        await fixture.load();
        final writing = fixture.chat.updateChannelMetadata(
          _site,
          9,
          name: 'Bugs :bug:',
        );
        await fixture.metadataStarted();
        // Publisher uses channel.title; ChannelSerializer also has unicode_title.
        fixture.editEvent('Bugs :bug:', 'bugs', _original.description);
        expect(fixture.channel.title, 'Bugs :bug:');
        fixture.metadataGate.complete();
        expect(await writing, isNull);
        expect(fixture.channel.title, 'Bugs 🐛');
        expect(fixture.channel.description, _original.description);
      },
    );

    test(
      'canonical text normalization only replaces submitted settings',
      () async {
        // The serializer omits a cleared description and supplies the category
        // title when a blank channel name resets it, plus the normalized slug.
        final response = ChatChannel.fromJson(const {
          'id': 9,
          'chatable_type': 'Category',
          'title': 'Category title',
          'slug': 'bugs-help',
          'threading_enabled': true,
          'status': 'closed',
        }, _site);
        final fixture = _Fixture(metadataResponse: response);
        await fixture.load();

        final writing = fixture.chat.updateChannelMetadata(
          _site,
          9,
          name: ' ',
          slug: 'Bugs & Help',
          description: '',
        );
        await fixture.metadataStarted();
        fixture.metadataGate.complete();
        expect(await writing, isNull);
        expect(
          fixture.channel,
          _original.withRemoteMetadata(
            title: 'Category title',
            slug: 'bugs-help',
            description: null,
          ),
        );
      },
    );

    test(
      'a slug-only response preserves the other text and threading',
      () async {
        final initial = _original.withThreadingEnabled(true);
        final fixture = _Fixture(
          initialChannel: initial,
          metadataResponse: _original.withRemoteMetadata(
            title: 'Stale title',
            slug: 'bugs-help',
            description: 'Stale description',
          ),
        );
        await fixture.load();
        final writing = fixture.chat.updateChannelMetadata(
          _site,
          9,
          slug: 'Bugs & Help',
        );
        await fixture.metadataStarted();
        fixture.metadataGate.complete();
        expect(await writing, isNull);
        expect(
          fixture.channel,
          initial.withRemoteMetadata(
            title: initial.title,
            slug: 'bugs-help',
            description: initial.description,
          ),
        );
      },
    );

    test(
      'a threading response preserves current metadata and its nullable slug',
      () async {
        final initial = ChatChannel.fromJson(const {
          'id': 9,
          'title': 'Bugs',
          'chatable_type': 'Category',
          'current_user_membership': {'following': true},
        }, _site);
        final fixture = _Fixture(
          initialChannel: initial,
          metadataResponse: _original.withThreadingEnabled(true),
        );
        await fixture.load();
        final writing = fixture.chat.updateChannelThreading(_site, 9, true);
        await fixture.metadataStarted();
        fixture.metadataGate.complete();
        expect(await writing, isNull);
        expect(fixture.channel, initial.withThreadingEnabled(true));
      },
    );

    test('a status response uses the canonical status', () async {
      final fixture = _Fixture(statusResponse: _original);
      await fixture.load();
      final writing = fixture.chat.setChannelClosed(_site, 9, closed: true);
      await fixture.statusStarted();
      fixture.statusGate.complete();
      expect(await writing, isNull);
      expect(fixture.channel.status, ChatChannelStatus.open);
    });

    test(
      'a live archive keeps unread state cleared after a close response',
      () async {
        final fixture = _Fixture();
        await fixture.load();
        final writing = fixture.chat.setChannelClosed(_site, 9, closed: true);
        await fixture.statusStarted();
        fixture.statusEvent('archived');
        fixture.statusGate.complete();
        expect(await writing, isNull);
        expect(fixture.channel.status, ChatChannelStatus.archived);
        expect(fixture.channel.tracking, ChatTracking.none);
      },
    );

    for (final statusWrite in [false, true]) {
      final kind = statusWrite ? 'status' : 'metadata';
      test(
        '$kind accepts its response after events preceding HTTP dispatch',
        () async {
          final fixture = _Fixture();
          await fixture.load();
          final credentialsGate = fixture.credentials.gate = Completer<void>();
          final writing = statusWrite
              ? fixture.chat.setChannelClosed(_site, 9, closed: true)
              : fixture.chat.updateChannelMetadata(
                  _site,
                  9,
                  description: 'Saved description',
                );
          await Future<void>.delayed(Duration.zero);
          expect(fixture.api.chatChannelMetadataUpdates, isEmpty);
          expect(fixture.api.chatChannelStatusesUpdated, isEmpty);
          fixture.editEvent('Earlier title', 'earlier-title', null);
          fixture.statusEvent('open');
          final beforeDispatch = fixture.channel;
          credentialsGate.complete();
          await (statusWrite
              ? fixture.statusStarted()
              : fixture.metadataStarted());
          (statusWrite ? fixture.statusGate : fixture.metadataGate).complete();
          expect(await writing, isNull);
          expect(
            fixture.channel,
            statusWrite
                ? beforeDispatch.withRemoteStatus(ChatChannelStatus.closed)
                : beforeDispatch.withRemoteMetadata(
                    title: beforeDispatch.title,
                    slug: beforeDispatch.slug,
                    description: 'Saved description',
                  ),
          );
        },
      );

      test('$kind ignores unrelated and invalid settings events', () async {
        final fixture = _Fixture();
        await fixture.load();
        final writing = statusWrite
            ? fixture.chat.setChannelClosed(_site, 9, closed: true)
            : fixture.chat.updateChannelMetadata(
                _site,
                9,
                description: 'Saved description',
              );
        await (statusWrite
            ? fixture.statusStarted()
            : fixture.metadataStarted());
        fixture.editEvent('Other', 'other', null, channelId: 10);
        fixture.statusEvent('closed', channelId: 10);
        fixture.deliver('/chat/channel-edits', {
          'chat_channel_id': 9,
          'description': 'Incomplete event',
        });
        fixture.statusEvent('invalid');
        (statusWrite ? fixture.statusGate : fixture.metadataGate).complete();
        expect(await writing, isNull);
        expect(
          fixture.channel,
          statusWrite
              ? _original.withRemoteStatus(ChatChannelStatus.closed)
              : _original.withRemoteMetadata(
                  title: _original.title,
                  slug: _original.slug!,
                  description: 'Saved description',
                ),
        );
      });

      test('$kind keeps the shared settings write lock', () async {
        final fixture = _Fixture();
        await fixture.load();
        final writing = statusWrite
            ? fixture.chat.setChannelClosed(_site, 9, closed: true)
            : fixture.chat.updateChannelMetadata(
                _site,
                9,
                description: 'Saved description',
              );
        await (statusWrite
            ? fixture.statusStarted()
            : fixture.metadataStarted());
        final blocked = statusWrite
            ? fixture.chat.updateChannelThreading(_site, 9, true)
            : fixture.chat.setChannelClosed(_site, 9, closed: true);
        expect(await blocked, 'Another channel change is still finishing.');
        expect(
          statusWrite
              ? fixture.api.chatChannelMetadataUpdates
              : fixture.api.chatChannelStatusesUpdated,
          isEmpty,
        );
        (statusWrite ? fixture.statusGate : fixture.metadataGate).complete();
        expect(await writing, isNull);
        expect(fixture.chat.channelSettingsWriteInFlight(_site, 9), isFalse);
      });

      for (final fails in [false, true]) {
        test(
          'retired $kind ${fails ? 'failure' : 'response'} leaves a replacement write alone',
          () async {
            const failure = WriteException(WriteFailure.forbidden);
            final fixture = _Fixture(
              metadataResponse: _original.withThreadingEnabled(true),
              metadataFailure: !statusWrite && fails ? failure : null,
              statusFailure: statusWrite && fails ? failure : null,
            );
            await fixture.load();
            final retired = statusWrite
                ? fixture.chat.setChannelClosed(_site, 9, closed: true)
                : fixture.chat.updateChannelThreading(_site, 9, true);
            await (statusWrite
                ? fixture.statusStarted()
                : fixture.metadataStarted());

            fixture.lifecycle.invalidate(_site);
            fixture.chat.forget(_site);
            fixture.chat.attachTracker(_site, fixture.tracker);
            await fixture.load();
            final replacement = statusWrite
                ? fixture.chat.updateChannelThreading(_site, 9, true)
                : fixture.chat.setChannelClosed(_site, 9, closed: true);
            await (statusWrite
                ? fixture.metadataStarted()
                : fixture.statusStarted());
            final current = fixture.channel;

            (statusWrite ? fixture.statusGate : fixture.metadataGate)
                .complete();
            await retired;
            expect(fixture.channel, current);
            expect(fixture.chat.channelSettingsWriteInFlight(_site, 9), isTrue);

            (statusWrite ? fixture.metadataGate : fixture.statusGate)
                .complete();
            expect(await replacement, isNull);
            expect(
              fixture.chat.channelSettingsWriteInFlight(_site, 9),
              isFalse,
            );
            expect(
              fixture.channel,
              statusWrite
                  ? _original.withThreadingEnabled(true)
                  : _original.withRemoteStatus(ChatChannelStatus.closed),
            );
          },
        );
      }
    }

    test(
      'threading rollback preserves live text, status and activity',
      () async {
        final fixture = _Fixture(
          metadataFailure: const WriteException(WriteFailure.forbidden),
        );
        await fixture.load();
        final writing = fixture.chat.updateChannelThreading(_site, 9, true);
        await fixture.metadataStarted();
        expect(fixture.channel.threadingEnabled, isTrue);
        fixture.editEvent('Support', 'support', 'Remote description');
        fixture.statusEvent('closed');
        fixture.activityEvents();
        final live = fixture.channel;

        fixture.metadataGate.complete();
        expect(await writing, isNotNull);
        expect(fixture.channel, live.withThreadingEnabled(false));
        expect(fixture.chat.channelSettingsWriteInFlight(_site, 9), isFalse);
      },
    );
  });
}

final class _Fixture {
  _Fixture({
    ChatChannel? initialChannel,
    ChatChannel? metadataResponse,
    ChatChannel? statusResponse,
    WriteException? metadataFailure,
    WriteException? statusFailure,
  }) {
    api = FakeDiscourseApi(
      chatChannelsBySite: {
        _site: ChatChannels(
          public: [
            initialChannel ?? _original,
            const ChatChannel(
              id: 10,
              title: 'Other channel',
              kind: ChatChannelKind.category,
              membership: ChatMembership(following: true),
            ),
          ],
          newMessageBusLastIds: const {9: 0},
          channelMetadataBusLastId: 0,
          channelEditsBusLastId: 0,
          channelStatusBusLastId: 0,
          userTrackingBusLastId: 0,
        ),
      },
      chatChannelUpdateResponse:
          metadataResponse ??
          _original.withRemoteMetadata(
            title: _original.title,
            slug: _original.slug!,
            description: 'Saved description',
          ),
      chatChannelUpdateGate: metadataGate,
      chatChannelUpdateFailure: metadataFailure,
      chatChannelStatusResponse:
          statusResponse ??
          _original.withRemoteStatus(ChatChannelStatus.closed),
      chatChannelStatusGate: statusGate,
      chatChannelStatusFailure: statusFailure,
    );
    chat = ChatController(
      api: api,
      requests: FakePluginRequestHost(
        credentials: credentials,
        lifecycle: lifecycle,
      ),
      store: Store(),
      currentUserFor: (_) =>
          const DiscourseUser(id: 7, username: 'staff', staff: true),
    );
    tracker = FakeSiteTracker(
      siteUrl: _site,
      onIncomingTopics: () {},
      onNotifications: (_) {},
      onReviewableCounts: (_) {},
      userId: 7,
      apiKey: 'key',
    );
    chat.attachTracker(_site, tracker);
    addTearDown(chat.dispose);
  }

  final metadataGate = Completer<void>();
  final statusGate = Completer<void>();
  final lifecycle = SiteLifecycle();
  final credentials = _Credentials()..keys[_site] = 'key';
  late final FakeDiscourseApi api;
  late final ChatController chat;
  late final FakeSiteTracker tracker;
  int _messageId = 0;

  ChatChannel get channel => chat.channel(_site, 9)!;

  Future<void> load() => chat.loadChannels(_site);

  Future<void> metadataStarted() async {
    await Future<void>.delayed(Duration.zero);
    expect(api.chatChannelMetadataUpdates, hasLength(1));
    expect(chat.channelSettingsWriteInFlight(_site, 9), isTrue);
  }

  Future<void> statusStarted() async {
    await Future<void>.delayed(Duration.zero);
    expect(api.chatChannelStatusesUpdated, hasLength(1));
    expect(chat.channelSettingsWriteInFlight(_site, 9), isTrue);
  }

  void deliver(String busChannel, Map<String, dynamic> data) =>
      tracker.deliverPluginMessage(busChannel, data, messageId: ++_messageId);

  void statusEvent(String status, {int channelId = 9}) => deliver(
    '/chat/channel-status',
    {'chat_channel_id': channelId, 'status': status},
  );

  void editEvent(
    String title,
    String slug,
    String? description, {
    int channelId = 9,
  }) => deliver('/chat/channel-edits', {
    'chat_channel_id': channelId,
    'name': title,
    'slug': slug,
    'description': description,
  });

  void activityEvents() {
    deliver('/chat/channel-metadata', {
      'chat_channel_id': 9,
      'memberships_count': 7,
    });
    deliver('/chat/9/new-messages', {
      'type': 'channel',
      'channel_id': 9,
      'message': {
        'id': 20,
        'chat_channel_id': 9,
        'created_at': '2026-09-08T11:00:00.000Z',
        'cooked': '<p>New activity</p>',
        'user': {'id': 8, 'username': 'author'},
      },
    });
    deliver('/chat/user-tracking-state/7', {
      'channel_id': 9,
      'last_read_message_id': 15,
      'unread_count': 1,
      'mention_count': 0,
    });
    expect(channel.membershipsCount, 7);
    expect(channel.lastMessageId, 20);
    expect(channel.lastMessageAt, DateTime.utc(2026, 9, 8, 11));
    expect(channel.membership.lastReadMessageId, 15);
  }
}

final class _Credentials extends FakeApiCredentialReader {
  Completer<void>? gate;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (gate case final pending?) await pending.future;
    return super.apiKeyFor(siteUrl);
  }
}
