import 'dart:async';

import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_members_session.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';

void main() {
  testWidgets('debounces and trims searches without repeating the same query', (
    tester,
  ) async {
    final chat = _Chat();
    final session = _session(chat);
    unawaited(session.refresh());
    chat.requests.single.complete([1]);
    await tester.pump();
    session.filterChanged('n');
    await tester.pump(const Duration(milliseconds: 200));
    session.filterChanged(' new ');
    await tester.pump(const Duration(milliseconds: 299));
    expect(chat.requests.length, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(chat.requests.last.username, 'new');
    expect(chat.requests.last.offset, 0);
    chat.requests.last.complete([90]);
    await tester.pump();
    session.filterChanged('new');
    await tester.pump(const Duration(milliseconds: 300));
    expect(chat.requests.length, 2);
    expect(_ids(session), [90]);
  });

  testWidgets(
    'uses server progress and retries errors without automatic prefetch',
    (tester) async {
      final chat = _Chat();
      final session = _session(chat);
      unawaited(session.refresh());
      chat.requests.last.complete([1, 1], rows: 20, more: true);
      await tester.pump();
      expect(_ids(session), [1]);
      unawaited(session.loadMore());
      unawaited(session.loadMore());
      expect(chat.requests.length, 2);
      expect(chat.requests.last.offset, 20);
      expect(chat.requests.last.limit, 20);
      chat.requests.last.complete([], rows: 20, more: true);
      await tester.pump();
      expect(session.canLoadMore, isTrue);
      expect(session.nextOffset, 40);
      unawaited(session.loadMore());
      chat.requests.last.result.complete((page: null, error: 'offline'));
      await tester.pump();
      expect(_ids(session), [1]);
      await session.loadMore(prefetch: true);
      expect(chat.requests.length, 3);
      unawaited(session.loadMore());
      expect(chat.requests.last.offset, 40);
      expect(session.error, isNull);
      chat.requests.last.complete([1, 2]);
      await tester.pump();
      expect(_ids(session), [1, 2]);
      expect(session.canLoadMore, isFalse);
    },
  );

  for (final fail in [false, true]) {
    testWidgets('rejects stale query ${fail ? 'failure' : 'success'}', (
      tester,
    ) async {
      final chat = _Chat();
      final session = _session(chat);
      unawaited(session.refresh());
      final old = chat.requests.single;
      session.filterChanged('new');
      await tester.pump(const Duration(milliseconds: 300));
      chat.requests.last.complete([90], rows: 20, more: true);
      await tester.pump();
      old.result.complete(
        fail ? (page: null, error: 'offline') : (page: _page([1]), error: null),
      );
      await tester.pump();
      expect(_ids(session), [90]);
      expect(session.error, isNull);
      expect(session.nextOffset, 20);
      expect(session.loading, isFalse);
    });
  }

  for (final identity in ['controller', 'site', 'channel']) {
    for (final fail in [false, true]) {
      testWidgets(
        'retires $identity requests with a late ${fail ? 'failure' : 'success'}',
        (tester) async {
          final chat = _Chat();
          final replacement = identity == 'controller' ? _Chat() : chat;
          final session = _session(chat);
          unawaited(session.refresh());
          final old = chat.requests.single;
          session.bind(
            chat: replacement,
            siteUrl: identity == 'site' ? 'https://other.discourse.org' : _site,
            channelId: identity == 'channel' ? 10 : 9,
            membershipsCount: 100,
          );
          final current = replacement.requests.last;
          expect(identical(old, current), isFalse);
          expect(current.offset, 0);
          current.complete([90]);
          await tester.pump();
          old.result.complete(
            fail
                ? (page: null, error: 'offline')
                : (page: _page([1]), error: null),
          );
          await tester.pump();
          expect(_ids(session), [90]);
          expect(session.error, isNull);
          expect(session.canLoadMore, isFalse);
        },
      );
    }
  }

  testWidgets(
    'keeps pending debounce across binding and refreshes count with the committed filter',
    (tester) async {
      final chat = _Chat();
      final session = _session(chat);
      unawaited(session.refresh());
      chat.requests.last.complete([1]);
      await tester.pump();
      session.filterChanged(' new ');
      await tester.pump(const Duration(milliseconds: 200));
      session.bind(
        chat: chat,
        siteUrl: _site,
        channelId: 10,
        membershipsCount: 100,
      );
      expect(chat.requests.last.channelId, 10);
      expect(chat.requests.last.username, '');
      chat.requests.last.complete([10]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(chat.requests.last.channelId, 10);
      expect(chat.requests.last.username, 'new');
      chat.requests.last.complete([90], rows: 20, more: true);
      await tester.pump();
      session.bind(
        chat: chat,
        siteUrl: _site,
        channelId: 10,
        membershipsCount: 101,
      );
      expect(chat.requests.last.username, 'new');
      expect(chat.requests.last.offset, 0);
      chat.requests.last.complete([91]);
      await tester.pump();
      final count = chat.requests.length;
      session.bind(
        chat: chat,
        siteUrl: _site,
        channelId: 10,
        membershipsCount: 101,
      );
      expect(chat.requests.length, count);
      expect(_ids(session), [91]);
    },
  );

  testWidgets(
    'admits before notifying and abandons dispatch after reentrant binding',
    (tester) async {
      final chat = _Chat();
      final session = _session(chat);
      var rebound = false;
      session.addListener(() {
        if (!session.loading || rebound) return;
        rebound = true;
        unawaited(session.loadMore());
        session.bind(
          chat: chat,
          siteUrl: _site,
          channelId: 10,
          membershipsCount: 100,
        );
      });
      unawaited(session.refresh());
      expect(chat.requests.length, 1);
      expect(chat.requests.single.channelId, 10);
      chat.requests.single.complete([10]);
      await tester.pump();
      expect(_ids(session), [10]);
    },
  );

  testWidgets('retires dispatch when a loading listener disposes the session', (
    tester,
  ) async {
    final chat = _Chat();
    final session = ChatChannelMembersSession(
      chat: chat,
      siteUrl: _site,
      channelId: 9,
      membershipsCount: 100,
    );
    session.addListener(session.dispose);
    await session.refresh();
    expect(chat.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal retires delayed results and debounce', (tester) async {
    final chat = _Chat();
    final session = ChatChannelMembersSession(
      chat: chat,
      siteUrl: _site,
      channelId: 9,
      membershipsCount: 100,
    );
    var notifications = 0;
    session.addListener(() => notifications++);
    unawaited(session.refresh());
    session.filterChanged('new');
    session.dispose();
    final before = notifications;
    chat.requests.single.complete([1]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifications, before);
    expect(chat.requests.length, 1);
  });
}

ChatChannelMembersSession _session(_Chat chat) {
  final session = ChatChannelMembersSession(
    chat: chat,
    siteUrl: _site,
    channelId: 9,
    membershipsCount: 100,
  );
  addTearDown(session.dispose);
  return session;
}

List<int> _ids(ChatChannelMembersSession session) =>
    session.members.map((member) => member.id).toList();

ChatChannelMembersPage _page(List<int> ids, {int? rows, bool more = false}) => (
  members: [for (final id in ids) ChatUser(id: id, username: 'member$id')],
  rowCount: rows ?? ids.length,
  totalRows: 100,
  canLoadMore: more,
);

class _Chat extends Fake implements ChatController {
  final requests = <_Request>[];

  @override
  Future<ChatChannelMembersResult> fetchChannelMembers(
    String siteUrl,
    int channelId, {
    String username = '',
    int offset = 0,
    int limit = 20,
  }) {
    final request = _Request(siteUrl, channelId, username, offset, limit);
    requests.add(request);
    return request.result.future;
  }
}

class _Request {
  _Request(
    this.siteUrl,
    this.channelId,
    this.username,
    this.offset,
    this.limit,
  );
  final String siteUrl;
  final int channelId;
  final String username;
  final int offset;
  final int limit;
  final result = Completer<ChatChannelMembersResult>();

  void complete(List<int> ids, {int? rows, bool more = false}) =>
      result.complete((page: _page(ids, rows: rows, more: more), error: null));
}
