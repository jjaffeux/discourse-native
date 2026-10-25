import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://thread-overview.example';

ChatChannel _parsed(
  Map<int, DateTime> overview, {
  int id = 1,
  DateTime? viewedAt,
  int? messageId,
  DateTime? messageAt,
}) => ChatChannel.fromJson(
  {
    'id': id,
    'title': 'Channel $id',
    'chatable_type': 'DirectMessage',
    'threading_enabled': true,
    'current_user_membership': {
      'following': true,
      'last_viewed_at': viewedAt?.toIso8601String(),
    },
    'last_message': {
      'id': messageId,
      'created_at': messageAt?.toIso8601String(),
    },
  },
  _site,
  unreadThreadOverview: overview,
);

void main() {
  final oldest = DateTime.utc(2026, 10, 1);
  final middle = DateTime.utc(2026, 10, 2);
  final newest = DateTime.utc(2026, 10, 3);

  test('parsed summaries own their input and reject map mutation', () {
    final input = {1: oldest, 2: middle, 3: newest};
    final channel = _parsed(input, viewedAt: middle);
    expect(channel.latestUnreadThreadAt, newest);
    expect(channel.lastUnreadThreadAt, oldest);
    expect(channel.unreadThreadsCountSinceLastViewed, 2);
    input[3] = oldest;
    input.clear();
    expect(channel.latestUnreadThreadAt, newest);
    expect(channel.lastUnreadThreadAt, oldest);
    expect(channel.unreadThreadsCountSinceLastViewed, 2);
    final overview = channel.unreadThreadOverview;
    for (final mutate in <void Function()>[
      () => overview[1] = newest,
      () => overview.addAll({4: newest}),
      () => overview.addEntries([MapEntry(4, newest)]),
      () => overview.clear(),
      () => overview.remove(1),
      () => overview.removeWhere((_, _) => true),
      () => overview.putIfAbsent(4, () => newest),
      () => overview.update(1, (_) => newest),
      () => overview.updateAll((_, _) => newest),
      () => overview.cast<num, DateTime>()[4] = newest,
    ]) {
      expect(mutate, throwsUnsupportedError);
      expect(overview, {1: oldest, 2: middle, 3: newest});
    }
  });

  test(
    'raw constructor maps remain live through copies and equal-size edits',
    () {
      final overview = {1: oldest, 2: middle};
      final channel = ChatChannel(
        id: 1,
        title: 'Channel',
        kind: ChatChannelKind.directMessage,
        unreadThreadOverview: overview,
        membership: ChatMembership(lastViewedAt: middle),
      );
      final preview = channel.withLastMessagePreview('Preview');
      expect(channel.latestUnreadThreadAt, middle);
      expect(channel.lastUnreadThreadAt, oldest);
      expect(channel.unreadThreadsCountSinceLastViewed, 1);
      overview[1] = newest;
      expect(channel.latestUnreadThreadAt, newest);
      expect(channel.lastUnreadThreadAt, middle);
      expect(preview.unreadThreadsCountSinceLastViewed, 2);
      overview.clear();
      expect(channel.latestUnreadThreadAt, isNull);
      expect(channel.lastUnreadThreadAt, isNull);
      expect(preview.unreadThreadsCountSinceLastViewed, 0);
    },
  );

  test('shared snapshots count inclusive cutoffs in either direction', () {
    final channel = _parsed({1: oldest, 2: middle, 3: newest});
    final preview = channel.withLastMessagePreview('Preview');
    expect(preview.unreadThreadOverview, same(channel.unreadThreadOverview));
    expect(channel.unreadThreadsCountSinceLastViewed, 3);
    for (final (cutoff, count) in [
      (middle, 2),
      (newest, 1),
      (newest.add(const Duration(microseconds: 1)), 0),
      (oldest, 3),
      (middle, 2),
    ]) {
      final viewed = preview.withLastViewedAt(cutoff);
      expect(viewed.unreadThreadOverview, same(channel.unreadThreadOverview));
      for (var repeat = 0; repeat < 3; repeat++) {
        expect(viewed.unreadThreadsCountSinceLastViewed, count);
        expect(viewed.latestUnreadThreadAt, newest);
        expect(viewed.lastUnreadThreadAt, oldest);
      }
    }
    expect(channel.unreadThreadsCountSinceLastViewed, 3);
  });

  test('authoritative tracking takes an owned replacement snapshot', () {
    final channel = _parsed({1: oldest});
    final input = {2: newest};
    final tracked = channel.withTrackingState(
      tracking: ChatTracking.none,
      unreadThreadOverview: input,
    );
    expect(tracked.latestUnreadThreadAt, newest);
    input[2] = oldest;
    input.clear();
    expect(tracked.unreadThreadOverview, {2: newest});
    expect(tracked.latestUnreadThreadAt, newest);
    expect(channel.latestUnreadThreadAt, oldest);
    final unchanged = tracked.withTrackingState(tracking: ChatTracking.none);
    expect(unchanged.unreadThreadOverview, same(tracked.unreadThreadOverview));
  });

  test('eager thread updates and removals replace derived bounds', () {
    final channel = _parsed({1: oldest, 2: middle, 3: newest});
    ChatChannel reply(ChatChannel held, DateTime at) => held.withNewMessage(
      20,
      at,
      markRead: false,
      incrementUnread: false,
      threadId: 3,
      markThreadUnread: true,
    );
    final equal = reply(channel, newest);
    expect(equal.latestUnreadThreadAt, newest);
    final updated = reply(equal, oldest);
    expect(updated.latestUnreadThreadAt, middle);
    expect(updated.lastUnreadThreadAt, oldest);
    final removed = updated.withNewMessage(
      21,
      oldest,
      markRead: false,
      incrementUnread: false,
      threadId: 2,
      markThreadRead: true,
    );
    expect(removed.unreadThreadOverview, {1: oldest, 3: oldest});
    expect(removed.latestUnreadThreadAt, oldest);
    expect(channel.latestUnreadThreadAt, newest);
    final archived = removed.withRemoteStatus(ChatChannelStatus.archived);
    expect(archived.latestUnreadThreadAt, isNull);
    expect(archived.lastUnreadThreadAt, isNull);
    expect(archived.unreadThreadsCountSinceLastViewed, 0);
  });

  test(
    'inbox keeps parsed activity and canonical replacements current',
    () async {
      final first = _parsed({1: oldest}, id: 1, viewedAt: middle);
      final second = _parsed({2: middle}, id: 2, viewedAt: oldest);
      final store = Store();
      final chat = ChatController(
        api: FakeDiscourseApi(
          chatChannelsBySite: {
            _site: ChatChannels(public: const [], direct: [first, second]),
          },
        ),
        requests: FakePluginRequestHost(
          credentials: FakeApiCredentialReader()..keys[_site] = 'key',
        ),
        store: store,
      );
      addTearDown(chat.dispose);
      await chat.loadChannels(_site);
      List<ChatChannel> project({bool unread = false}) =>
          chatInboxConversations(
            chat,
            _site,
            ChatInboxFilter(unreadOnly: unread),
          );
      for (var repeat = 0; repeat < 3; repeat++) {
        expect(project().map((c) => c.id), [2, 1]);
        expect(project(unread: true).map((c) => c.id), [2]);
      }
      final tracked = first.withTrackingState(
        tracking: ChatTracking.none,
        unreadThreadOverview: {1: newest},
      );
      store.put(_site, tracked);
      expect(project().map((c) => c.id), [1, 2]);
      expect(project(unread: true).map((c) => c.id), [1, 2]);
      final preview = tracked.withLastMessagePreview('New preview');
      store.put(_site, preview);
      expect(project().first, same(preview));
      expect(project(unread: true).first, same(preview));
      store.put(
        _site,
        preview.withLastViewedAt(newest.add(const Duration(seconds: 1))),
      );
      expect(project(unread: true).map((c) => c.id), [2]);
      store.remove<ChatChannel>(_site, 1);
      expect(project().map((c) => c.id), [2]);
    },
  );

  test('inbox ignores placeholder message dates and preserves latest ties', () {
    expect(
      chatInboxActivityAt(_parsed({}, messageId: 0, messageAt: newest)),
      isNull,
    );
    expect(
      chatInboxActivityAt(
        _parsed({1: middle}, messageId: 0, messageAt: newest),
      ),
      middle,
    );
    expect(
      chatInboxActivityAt(
        _parsed({1: middle}, messageId: 10, messageAt: newest),
      ),
      newest,
    );
    expect(
      chatInboxActivityAt(
        _parsed({1: newest}, messageId: 10, messageAt: middle),
      ),
      newest,
    );
    expect(
      chatInboxActivityAt(
        _parsed({1: newest}, messageId: 10, messageAt: newest),
      ),
      newest,
    );
  });
}
