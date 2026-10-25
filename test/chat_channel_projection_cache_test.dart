import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/counting_thread_overview.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _section = ChatChannelListSection.directMessages;

DiscourseUser _user({String filter = 'all', String sort = 'alphabetical'}) =>
    DiscourseUser(
      id: 7,
      username: 'reader',
      plugins: PluginData.none.withValue(
        chatCurrentUserDataKey,
        ChatCurrentUser(
          canChat: true,
          hasChatEnabled: true,
          channelListPreferences: ChatChannelListPreferences.read({
            for (final section in ChatChannelListSection.values) ...{
              section.filterField: filter,
              section.sortField: sort,
            },
          }),
        ),
      ),
    );

class _Counter {
  int value = 0;
}

class _CountingChannel extends ChatChannel {
  _CountingChannel(int id)
    : super(
        id: id,
        title: 'Channel ${((id * 37) % 75).toString().padLeft(2, '0')}',
        kind: ChatChannelKind.directMessage,
        membership: const ChatMembership(following: true),
      );

  final titleReads = _Counter();

  @override
  String get title {
    titleReads.value++;
    return super.title;
  }
}

ChatChannel _channel(int id, {DateTime? activityAt}) => ChatChannel(
  id: id,
  title: 'Channel ${id.toString().padLeft(2, '0')}',
  kind: ChatChannelKind.directMessage,
  membership: const ChatMembership(following: true),
  lastMessageId: activityAt == null ? null : id,
  lastMessageAt: activityAt,
);

Future<({ChatController chat, Store store, FakeDiscourseApi api})> _fixture(
  List<ChatChannel> channels, {
  DiscourseUser? Function(String)? currentUserFor,
  DateTime Function()? clock,
}) async {
  final api = FakeDiscourseApi(
    chatChannelsBySite: {
      _site: ChatChannels(public: const [], direct: channels),
    },
  );
  final store = Store();
  final chat = ChatController(
    api: api,
    store: store,
    requests: FakePluginRequestHost(
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
    ),
    currentUserFor: currentUserFor ?? (_) => _user(),
    clock: clock,
  );
  addTearDown(chat.dispose);
  await chat.loadChannels(_site);
  return (chat: chat, store: store, api: api);
}

void main() {
  test(
    'cold and warm unread projections visit each thread only once',
    () async {
      final now = DateTime.utc(2026, 10, 24);
      final overview = CountingThreadOverview({
        for (var id = 0; id < 32; id++) id: now,
      });
      final subject = await _fixture([
        for (var id = 1; id <= 64; id++)
          ChatChannel(
            id: id,
            title: 'Channel $id',
            kind: ChatChannelKind.directMessage,
            membership: ChatMembership(following: true, lastViewedAt: now),
            threadingEnabled: true,
            unreadThreadOverview: overview,
          ),
      ], currentUserFor: (_) => _user(filter: 'unread', sort: 'priority'));
      for (var lookup = 0; lookup < 2; lookup++) {
        overview.visits = 0;
        expect(subject.chat.channelList(_site, _section), hasLength(50));
        expect(overview.visits, lessThanOrEqualTo(64 * 32));
      }
      overview.clear();
      expect(subject.chat.channelList(_site, _section), isEmpty);
    },
  );

  for (final filter in ['all', 'mentions', 'active']) {
    test(
      'priority $filter avoids thread scans for urgent or excluded rows',
      () async {
        final now = DateTime.utc(2026, 10, 24);
        final overview = CountingThreadOverview({
          for (var id = 0; id < 32; id++) id: now,
        });
        final subject = await _fixture(
          [
            for (var id = 1; id <= 64; id++)
              ChatChannel(
                id: id,
                title: 'Channel $id',
                kind: ChatChannelKind.directMessage,
                membership: ChatMembership(following: true, lastViewedAt: now),
                tracking: filter == 'all'
                    ? const ChatTracking(mentionCount: 1)
                    : ChatTracking.none,
                threadingEnabled: true,
                unreadThreadOverview: overview,
              ),
          ],
          currentUserFor: (_) => _user(filter: filter, sort: 'priority'),
          clock: () => now,
        );
        for (var lookup = 0; lookup < 2; lookup++) {
          overview.visits = 0;
          expect(
            subject.chat.channelList(_site, _section),
            hasLength(filter == 'all' ? 50 : 0),
          );
          expect(overview.visits, 0);
        }
      },
    );
  }
  test(
    'unchanged preference lists only read each title once per lookup',
    () async {
      final channels = [for (var id = 1; id <= 75; id++) _CountingChannel(id)];
      final subject = await _fixture(channels);
      List<int> project() => subject.chat
          .channelList(_site, _section)
          .map((channel) => channel.id)
          .toList();
      final expected = [
        for (var id = 75; id > 0; id -= 2) id,
        for (var id = 74; id >= 52; id -= 2) id,
      ];
      expect(project(), expected);
      for (final channel in channels) {
        channel.titleReads.value = 0;
      }
      for (var iteration = 0; iteration < 20; iteration++) {
        expect(project(), expected);
      }
      final reads = channels.fold(
        0,
        (sum, channel) => sum + channel.titleReads.value,
      );
      expect(reads, lessThanOrEqualTo(75 * 20));
    },
  );

  test(
    'DM limit, active retention, starring and filter changes stay current',
    () async {
      var user = _user();
      final subject = await _fixture([
        for (var id = 1; id <= 60; id++) _channel(id),
      ], currentUserFor: (_) => user);
      List<int> project({bool sidebar = true, int? active}) => subject.chat
          .channelList(
            _site,
            _section,
            sidebar: sidebar,
            activeChannelId: active,
          )
          .map((channel) => channel.id)
          .toList();
      expect(project(), [for (var id = 1; id <= 50; id++) id]);
      expect(project(active: 60), [for (var id = 1; id < 50; id++) id, 60]);
      expect(project(sidebar: false, active: 60), [
        for (var id = 1; id <= 50; id++) id,
      ]);
      subject.store.put(_site, _channel(1).withStarred(true));
      expect(project().first, 2);
      expect(
        subject.chat
            .channelList(_site, ChatChannelListSection.starred)
            .single
            .id,
        1,
      );
      user = _user(filter: 'mentions');
      expect(project(), isEmpty);
      expect(project(active: 60), [60]);
      user = _user();
      expect(project().first, 2);
    },
  );

  test(
    'active filter expires immediately after its inclusive 30-day boundary',
    () async {
      final activityAt = DateTime.utc(2026, 9, 24, 12);
      var now = activityAt.add(const Duration(days: 30));
      final subject = await _fixture(
        [_channel(1, activityAt: activityAt)],
        currentUserFor: (_) => _user(filter: 'active'),
        clock: () => now,
      );
      expect(subject.chat.channelList(_site, _section).single.id, 1);
      expect(subject.chat.channelList(_site, _section).single.id, 1);
      now = now.add(const Duration(microseconds: 1));
      expect(subject.chat.channelList(_site, _section), isEmpty);
      expect(
        subject.chat.channelList(_site, _section, activeChannelId: 1).single.id,
        1,
      );
      now = activityAt;
      expect(subject.chat.channelList(_site, _section).single.id, 1);
    },
  );

  test(
    'cached IDs resolve preview replacements and disappear with store rows',
    () async {
      final subject = await _fixture([_channel(1), _channel(2)]);
      const filter = ChatInboxFilter();
      subject.chat.channelList(_site, _section);
      chatInboxConversations(subject.chat, _site, filter);
      final edited = _channel(1).withLastMessagePreview('Fresh preview');
      subject.store.put(_site, edited);
      expect(subject.chat.channelList(_site, _section).first, same(edited));
      expect(
        chatInboxConversations(subject.chat, _site, filter).first,
        same(edited),
      );
      subject.store.remove<ChatChannel>(_site, 1);
      expect(subject.chat.channelList(_site, _section).map((c) => c.id), [2]);
      expect(
        chatInboxConversations(subject.chat, _site, filter).map((c) => c.id),
        [2],
      );
    },
  );

  test('forgetting an account drops its cached query results', () async {
    final subject = await _fixture([_channel(1), _channel(2)]);
    const filter = ChatInboxFilter();
    expect(subject.chat.channelList(_site, _section), hasLength(2));
    expect(chatInboxConversations(subject.chat, _site, filter), hasLength(2));
    subject.chat.forget(_site);
    expect(subject.chat.channelList(_site, _section), isEmpty);
    expect(chatInboxConversations(subject.chat, _site, filter), isEmpty);
    subject.api.chatChannelsBySite[_site] = ChatChannels(
      public: const [],
      direct: [_channel(3)],
    );
    await subject.chat.loadChannels(_site);
    expect(subject.chat.channelList(_site, _section).single.id, 3);
    expect(chatInboxConversations(subject.chat, _site, filter).single.id, 3);
  });
}
