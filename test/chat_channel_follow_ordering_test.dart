import 'dart:async';

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_session.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

/// The channel panel joins and leaves from one chip, so a reader can ask for
/// both within one round trip. These pin which answer is allowed to land.
void main() {
  test('a leave asked while a join is unanswered waits its turn, so a join '
      'answered late cannot land over the leave', () async {
    final (chat, api, _) = _fixture();
    final design = _channel(10);

    final joining = chat.updateChannelFollowing(_site, design, true);
    await pumpEventQueue();
    expect(api.writes, [(channelId: 10, following: true)]);
    expect(chat.channelFollowWriteInFlight(_site, 10), isTrue);

    final refused = await chat.updateChannelFollowing(
      _site,
      design.withMembership(const ChatMembership(following: true)),
      false,
    );
    expect(refused, 'Another channel change is still finishing.');
    expect(
      api.writes,
      hasLength(1),
      reason: 'The leave was not sent ahead of the join it would undo',
    );

    api.answers.single.complete(const ChatMembership(following: true));
    expect(await joining, isNull);
    expect(chat.channel(_site, 10)?.membership.following, isTrue);
    expect(chat.publicChannels(_site).map((channel) => channel.id), [10]);
    expect(chat.channelFollowWriteInFlight(_site, 10), isFalse);

    final leaving = chat.updateChannelFollowing(
      _site,
      chat.channel(_site, 10)!,
      false,
    );
    await pumpEventQueue();
    expect(api.writes.last, (channelId: 10, following: false));
    api.answers.last.complete(const ChatMembership(following: false));
    expect(await leaving, isNull);
    expect(chat.channel(_site, 10)?.membership.following, isFalse);
    expect(chat.publicChannels(_site), isEmpty);
  });

  test('a join answered after its account has gone joins nothing', () async {
    final (chat, api, requests) = _fixture();
    var notified = 0;
    chat.addListener(() => notified++);

    final joining = chat.updateChannelFollowing(_site, _channel(10), true);
    await pumpEventQueue();
    expect(api.writes, hasLength(1));

    requests.lifecycle.invalidate(_site);
    final before = notified;
    api.answers.single.complete(const ChatMembership(following: true));
    expect(await joining, isNull);

    expect(chat.channel(_site, 10)?.membership.following, isNot(isTrue));
    expect(chat.publicChannels(_site), isEmpty);
    expect(chat.channelFollowWriteInFlight(_site, 10), isFalse);
    expect(notified, before, reason: 'The next account hears nothing of it');
  });

  test('a page asked for before a join or a leave and answered after it '
      'lists the channel where it now belongs', () async {
    final (chat, api, _) = _fixture();
    chat.inboxFilters.browseFor(_site)
      ..status = ChatChannelBrowseStatus.all
      ..membership = ChatChannelJoinedFilter.notJoined;
    final session = ChatBrowseSession(chat: chat, siteUrl: _site);
    addTearDown(session.dispose);

    final first = session.refresh();
    await pumpEventQueue();
    api.pages.single.complete(
      ChatChannelBrowsePage(channels: [_channel(10), _channel(11)]),
    );
    await first;
    expect(session.visibleChannels.map((channel) => channel.id), [10, 11]);

    // The page is read while the reader is not in the channel, and answered
    // once they are.
    final stale = session.refresh();
    await pumpEventQueue();
    final joining = chat.updateChannelFollowing(_site, _channel(10), true);
    await pumpEventQueue();
    api.answers.single.complete(const ChatMembership(following: true));
    expect(await joining, isNull);
    api.pages.last.complete(
      ChatChannelBrowsePage(channels: [_channel(10), _channel(11)]),
    );
    await stale;
    expect(session.visibleChannels.map((channel) => channel.id), [
      11,
    ], reason: 'The page still says not joined; the join answered since');

    session.changeMembership(ChatChannelJoinedFilter.joined);
    expect(session.visibleChannels.map((channel) => channel.id), [10]);
    final staleJoined = session.refresh();
    await pumpEventQueue();
    final leaving = chat.updateChannelFollowing(
      _site,
      chat.channel(_site, 10)!,
      false,
    );
    await pumpEventQueue();
    api.answers.last.complete(const ChatMembership(following: false));
    expect(await leaving, isNull);
    api.pages.last.complete(
      ChatChannelBrowsePage(
        channels: [_channel(10, following: true), _channel(11)],
      ),
    );
    await staleJoined;
    expect(
      session.visibleChannels,
      isEmpty,
      reason: 'The page still says joined; the leave answered since',
    );
  });
}

(ChatController, _FollowApi, FakePluginRequestHost) _fixture() {
  final api = _FollowApi();
  final requests = FakePluginRequestHost(
    credentials: FakeApiCredentialReader()..keys[_site] = 'key',
  );
  final chat = ChatController(api: api, requests: requests, store: Store());
  addTearDown(chat.dispose);
  return (chat, api, requests);
}

ChatChannel _channel(int id, {bool following = false}) => ChatChannel(
  id: id,
  title: 'Channel $id',
  kind: ChatChannelKind.category,
  canJoin: true,
  membership: ChatMembership(following: following),
);

class _FollowApi extends FakeDiscourseApi {
  final writes = <({int channelId, bool following})>[];
  final answers = <Completer<ChatMembership>>[];
  final pages = <Completer<ChatChannelBrowsePage>>[];

  Future<ChatMembership> _write(int channelId, bool following) {
    writes.add((channelId: channelId, following: following));
    final answer = Completer<ChatMembership>();
    answers.add(answer);
    return answer.future;
  }

  @override
  Future<ChatMembership> followChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) => _write(channelId, true);

  @override
  Future<ChatMembership> unfollowChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) => _write(channelId, false);

  @override
  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  }) {
    final page = Completer<ChatChannelBrowsePage>();
    pages.add(page);
    return page.future;
  }
}
