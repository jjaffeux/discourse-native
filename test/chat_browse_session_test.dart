import 'dart:async';

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_session.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

void main() {
  testWidgets('server rows drive hidden, duplicate and zero-row pages', (
    tester,
  ) async {
    final (session, api, _) = _fixture();
    session.changeMembership(ChatChannelJoinedFilter.joined);
    final first = session.refresh();
    await tester.pump();
    api.responses[0].complete(_decodedPage([1], rowCount: 25));
    await first;
    expect(session.visibleChannels, isEmpty);
    expect(session.hasMore, isTrue);

    final next = session.loadMore();
    await session.loadMore();
    await tester.pump();
    expect(api.calls.map((call) => call.offset), [0, 25]);
    expect(session.loadingMore, isTrue);
    api.responses[1].complete(
      _decodedPage([1, 2], rowCount: 4, following: {2}),
    );
    await next;
    expect(session.visibleChannels.map((channel) => channel.id), [2]);
    session.changeMembership(ChatChannelJoinedFilter.all);
    expect(session.visibleChannels.map((channel) => channel.id), [1, 2]);

    final last = session.loadMore();
    await tester.pump();
    expect(api.calls.last.offset, 29);
    api.responses[2].complete(const ChatChannelBrowsePage(hasMore: true));
    await last;
    expect(session.hasMore, isFalse);
    await session.loadMore();
    expect(api.calls, hasLength(3));
  });

  testWidgets('a failed page needs explicit retry at the same offset', (
    tester,
  ) async {
    final (session, api, _) = _fixture();
    final first = session.refresh();
    await tester.pump();
    api.responses[0].complete(
      ChatChannelBrowsePage(channels: [_channel(1)], hasMore: true),
    );
    await first;
    final next = session.loadMore();
    await tester.pump();
    api.responses[1].completeError(StateError('offline'));
    await next;
    expect(session.error, isNotNull);
    expect(session.loadingMore, isFalse);
    expect(session.visibleChannels.single.id, 1);
    await session.loadMore();
    expect(api.calls, hasLength(2));

    final retry = session.loadMore(retry: true);
    await tester.pump();
    expect(api.calls.map((call) => call.offset), [0, 1, 1]);
    api.responses[2].complete(ChatChannelBrowsePage(channels: [_channel(2)]));
    await retry;
    expect(session.error, isNull);
    expect(session.visibleChannels.map((channel) => channel.id), [1, 2]);
  });

  testWidgets('pending query cannot borrow the previous cursor', (
    tester,
  ) async {
    final (session, api, chat) = _fixture();
    final first = session.refresh();
    await tester.pump();
    api.responses[0].complete(
      ChatChannelBrowsePage(channels: [_channel(1)], hasMore: true),
    );
    await first;
    session.changeQuery('n');
    await tester.pump(const Duration(milliseconds: 200));
    session.changeQuery('new');
    await session.loadMore(retry: true);
    await tester.pump(const Duration(milliseconds: 349));
    expect(api.calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(api.calls.last, (
      filter: 'new',
      status: ChatChannelBrowseStatus.all,
      offset: 0,
    ));
    expect(chat.inboxFilters.browseFor(_site).query, 'new');
    api.responses[1].complete(ChatChannelBrowsePage(channels: [_channel(3)]));
    await tester.pump();
    expect(session.visibleChannels.single.id, 3);
  });

  testWidgets('a dispatched request may settle before query debounce expires', (
    tester,
  ) async {
    final (session, api, _) = _fixture();
    final first = session.refresh();
    await tester.pump();
    session.changeQuery('next');
    api.responses[0].complete(ChatChannelBrowsePage(channels: [_channel(1)]));
    await first;
    expect(session.visibleChannels.single.id, 1);
    expect(api.calls.single.filter, '');
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.calls.last.filter, 'next');
    expect(api.calls.last.offset, 0);
    api.responses[1].complete(ChatChannelBrowsePage(channels: [_channel(2)]));
    await tester.pump();
    expect(session.visibleChannels.single.id, 2);
  });

  testWidgets('status commits a pending query once with immutable inputs', (
    tester,
  ) async {
    final (session, api, _) = _fixture();
    session.changeQuery('new');
    session.changeStatus(ChatChannelBrowseStatus.closed);
    await tester.pump();
    expect(api.calls.single, (
      filter: 'new',
      status: ChatChannelBrowseStatus.closed,
      offset: 0,
    ));
    api.responses[0].complete(const ChatChannelBrowsePage());
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.calls, hasLength(1));
    expect(session.loading, isFalse);
  });

  testWidgets('a reset supersedes append without stale loading settlement', (
    tester,
  ) async {
    final (session, api, _) = _fixture();
    final first = session.refresh();
    await tester.pump();
    api.responses[0].complete(
      ChatChannelBrowsePage(channels: [_channel(1)], hasMore: true),
    );
    await first;
    final append = session.loadMore();
    await tester.pump();
    session.changeQuery('new');
    final reset = session.refresh();
    await tester.pump();
    api.responses[1].complete(ChatChannelBrowsePage(channels: [_channel(2)]));
    await append;
    expect(session.loading, isTrue);
    expect(session.loadingMore, isFalse);
    api.responses[2].complete(ChatChannelBrowsePage(channels: [_channel(3)]));
    await reset;
    expect(session.visibleChannels.single.id, 3);
    expect(session.loading, isFalse);
  });

  testWidgets('retirement cancels debounce and ignores delayed completion', (
    tester,
  ) async {
    final (session, api, chat) = _fixture(disposeSession: false);
    var notifications = 0;
    session.addListener(() => notifications++);
    final old = session.refresh();
    await tester.pump();
    session.changeQuery('saved');
    session.dispose();
    final replacement = ChatBrowseSession(chat: chat, siteUrl: _site);
    addTearDown(replacement.dispose);
    expect(replacement.query, 'saved');
    final current = replacement.refresh();
    await tester.pump();
    api.responses[1].complete(ChatChannelBrowsePage(channels: [_channel(2)]));
    await current;
    api.responses[0].complete(ChatChannelBrowsePage(channels: [_channel(1)]));
    await old;
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.calls, hasLength(2));
    expect(notifications, 1);
    expect(replacement.visibleChannels.single.id, 2);
  });

  testWidgets('reentrant refresh dispatches only the current request', (
    tester,
  ) async {
    final (session, api, _) = _fixture();
    var reset = false;
    Future<void>? replacement;
    session.addListener(() {
      if (reset) return;
      reset = true;
      session.changeQuery('replacement');
      replacement = session.refresh();
    });
    await session.refresh();
    await tester.pump();
    expect(api.calls.single.filter, 'replacement');
    api.responses.single.complete(const ChatChannelBrowsePage());
    await replacement;
    expect(session.loading, isFalse);
  });
}

(ChatBrowseSession, _BrowseApi, ChatController) _fixture({
  bool disposeSession = true,
}) {
  final api = _BrowseApi();
  final chat = ChatController(
    api: api,
    requests: FakePluginRequestHost(
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
    ),
    store: Store(),
  );
  addTearDown(chat.dispose);
  final session = ChatBrowseSession(chat: chat, siteUrl: _site);
  if (disposeSession) addTearDown(session.dispose);
  return (session, api, chat);
}

ChatChannel _channel(int id, {bool following = false}) => ChatChannel(
  id: id,
  title: 'Channel $id',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: following),
);

class _BrowseApi extends FakeDiscourseApi {
  final calls =
      <({String filter, ChatChannelBrowseStatus status, int offset})>[];
  final responses = <Completer<ChatChannelBrowsePage>>[];

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
    calls.add((filter: filter, status: status, offset: offset));
    final response = Completer<ChatChannelBrowsePage>();
    responses.add(response);
    return response.future;
  }
}

ChatChannelBrowsePage _decodedPage(
  List<int> ids, {
  required int rowCount,
  Set<int> following = const {},
}) => ChatChannelBrowsePage.fromJson(
  {
    'channels': [
      for (final id in ids)
        {
          'id': id,
          'title': 'Channel $id',
          'chatable_type': 'Category',
          'current_user_membership': {'following': following.contains(id)},
        },
      ...List<Object?>.filled(rowCount - ids.length, null),
    ],
    'meta': const {'load_more_url': '/next'},
  },
  _site,
  limit: rowCount,
);
