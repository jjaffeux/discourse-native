import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_channel_filter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  testWidgets(
    'channel search loads an unvisited channel directly and retains it',
    (tester) async {
      const design = ChatChannel(
        id: 10,
        title: 'design',
        kind: ChatChannelKind.category,
        threadingEnabled: true,
      );
      const empty = ChatChannel(
        id: 11,
        title: 'empty channel',
        kind: ChatChannelKind.category,
        threadingEnabled: true,
      );
      final api = FakeDiscourseApi(
        user: _user,
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
            channels: [_general],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(filter: 'design'):
              const ChatChannelBrowsePage(channels: [design]),
          FakeDiscourseApi.chatBrowseKey(filter: 'empty'):
              const ChatChannelBrowsePage(channels: [empty]),
        },
        chatChannelThreadPagesByKey: {
          ..._generalPages(),
          FakeDiscourseApi.chatChannelThreadPageKey(
            10,
            0,
          ): const ChatThreadPage(
            threads: [
              ChatThread(
                id: 10,
                channelId: 10,
                status: 'open',
                title: 'Design thread',
                lastMessageId: 101,
                replyCount: 1,
              ),
            ],
          ),
          FakeDiscourseApi.chatChannelThreadPageKey(11, 0):
              const ChatThreadPage(threads: []),
        },
      );
      final controller = await _pump(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('chat-threads-channel-filter')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'design');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('design'), findsWidgets);
      expect(_threadPages(api), [(9, 0)]);
      await tester.tap(
        find.descendant(
          of: find.byType(DCommandList<int>),
          matching: find.text('design'),
        ),
      );
      await tester.pumpAndSettle();
      expect(_threadPages(api), [(9, 0), (10, 0)]);
      expect(find.text('Design thread'), findsOneWidget);
      expect(find.text('Thread 1'), findsNothing);
      expect(
        api.chatBrowseRequested.every((request) => request.offset == 0),
        isTrue,
      );

      final reads = api.chatBrowseRequested.length;
      await _mount(tester, controller, shown: false);
      await _mount(tester, controller);
      await tester.pumpAndSettle();
      expect(api.chatBrowseRequested, hasLength(reads));
      expect(find.text('Design thread'), findsOneWidget);
      expect(
        tester
            .widget<ChatThreadChannelFilter>(
              find.byType(ChatThreadChannelFilter),
            )
            .selected
            ?.id,
        10,
      );
      await controller.pluginSession
          .require(chatShellService)
          .hydratePluginRoute(_site, ChatPlugin.myThreadsRouteId, force: true);
      await tester.pumpAndSettle();
      expect(_threadPages(api), [(9, 0), (10, 0), (10, 0), (10, 0)]);
      expect(api.chatBrowseRequested, hasLength(reads));

      await tester.tap(
        find.byKey(const ValueKey('chat-threads-channel-filter')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'empty');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DCommandList<int>),
          matching: find.text('empty channel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No threads in this channel.'), findsOneWidget);
      expect(find.text('Design thread'), findsNothing);
      expect(_threadPages(api), [(9, 0), (10, 0), (10, 0), (10, 0), (11, 0)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a late channel lookup cannot replace newer search results', (
    tester,
  ) async {
    const design = ChatChannel(
      id: 10,
      title: 'design',
      kind: ChatChannelKind.category,
      threadingEnabled: true,
    );
    final api = _ChannelLookupApi(
      user: _user,
      chatBrowsePagesByKey: {
        ..._browsePages,
        FakeDiscourseApi.chatBrowseKey(filter: 'design'):
            const ChatChannelBrowsePage(channels: [design]),
      },
      chatChannelThreadPagesByKey: _generalPages(),
    );
    await _pump(tester, api);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    api.browseGate = gate;
    await tester.tap(find.byKey(const ValueKey('chat-threads-channel-filter')));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Loading…'), findsNothing);
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    expect(find.byType(DSkeleton), findsWidgets);
    expect(find.text('All channels'), findsOneWidget);
    api.browseGate = null;
    await tester.enterText(find.byType(EditableText), 'design');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    Finder option(String text) => find.descendant(
      of: find.byType(DCommandList<int>),
      matching: find.text(text),
    );
    expect(option('design'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(option('design'), findsOneWidget);
    expect(option('general'), findsNothing);
    expect(_threadPages(api), [(9, 0)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel choices page and retry without loading their threads', (
    tester,
  ) async {
    const design = ChatChannel(
      id: 10,
      title: 'design',
      kind: ChatChannelKind.category,
      threadingEnabled: true,
    );
    const archive = ChatChannel(
      id: 11,
      title: 'design archive',
      kind: ChatChannelKind.category,
      threadingEnabled: true,
    );
    final pages = {
      ..._browsePages,
      FakeDiscourseApi.chatBrowseKey(filter: 'design'):
          const ChatChannelBrowsePage(channels: [design], hasMore: true),
    };
    final api = FakeDiscourseApi(
      user: _user,
      chatBrowsePagesByKey: pages,
      chatChannelThreadPagesByKey: _generalPages(),
    );
    await _pump(tester, api);
    await tester.tap(find.byKey(const ValueKey('chat-threads-channel-filter')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'design');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    Finder option(String text) => find.descendant(
      of: find.byType(DCommandList<int>),
      matching: find.text(text),
    );
    await tester.tap(option('Load more'));
    await tester.pumpAndSettle();
    expect(option('Try again'), findsOneWidget);
    pages[FakeDiscourseApi.chatBrowseKey(filter: 'design', offset: 1)] =
        const ChatChannelBrowsePage(channels: [archive]);
    await tester.tap(option('Try again'));
    await tester.pumpAndSettle();
    expect(option('design'), findsOneWidget);
    expect(option('design archive'), findsOneWidget);
    expect(option('Load more'), findsNothing);
    expect(
      api.chatBrowseRequested
          .where((request) => request.filter == 'design')
          .map((request) => request.offset),
      [0, 1, 1],
    );
    expect(_threadPages(api), [(9, 0)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thread badges show ordinary or urgent counts and cap at 99+', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: _user,
      chatBrowsePagesByKey: _browsePages,
      chatChannelThreadPagesByKey: {
        FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
          threads: [
            _thread(1).copyWith(tracking: const ChatTracking(unreadCount: 7)),
            _thread(2).copyWith(
              tracking: const ChatTracking(
                unreadCount: 20,
                mentionCount: 2,
                watchedThreadsUnreadCount: 3,
              ),
            ),
            _thread(3).copyWith(tracking: const ChatTracking(unreadCount: 123)),
            _thread(4),
          ],
        ),
      },
    );
    await _pump(tester, api);
    for (final (id, label) in [(1, '7'), (2, '5'), (3, '99+')]) {
      final badge = find.byKey(ValueKey('chat-my-thread-unread-$id'));
      expect(
        find.descendant(of: badge, matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: badge, matching: find.byType(DBadge)),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('chat-my-thread-unread-4')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed page waits for Try again instead of scrolling', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: _user,
      chatBrowsePagesByKey: {
        FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
          channels: [
            ChatChannel(
              id: 9,
              title: 'general',
              kind: ChatChannelKind.category,
              threadingEnabled: true,
            ),
          ],
        ),
      },
      chatChannelThreadPagesByKey: {
        FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
          threads: [for (var id = 1; id <= 20; id++) _thread(id)],
          hasMore: true,
        ),
      },
    );
    await _pump(tester, api);
    Iterable<int> offsets() =>
        api.chatChannelThreadPagesRequested.map((request) => request.offset);
    expect(offsets(), [0]);

    final list = find.byKey(const PageStorageKey('chat-my-threads'));
    await tester.fling(list, const Offset(0, -6000), 6000);
    await tester.pumpAndSettle();
    for (var drag = 0; drag < 5; drag++) {
      await tester.drag(list, const Offset(0, 40));
      await tester.drag(list, const Offset(0, -40));
      await tester.pumpAndSettle();
    }

    expect(offsets(), [0, 20]);
    expect(find.text('Could not load this channel’s threads.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(offsets(), [0, 20, 20]);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('Try again after a failed refresh reloads the first page', (
    tester,
  ) async {
    final firstPage = FakeDiscourseApi.chatChannelThreadPageKey(9, 0);
    final pages = {
      firstPage: ChatThreadPage(threads: [_thread(1)]),
    };
    final api = FakeDiscourseApi(
      user: _user,
      chatBrowsePagesByKey: _browsePages,
      chatChannelThreadPagesByKey: pages,
    );
    final controller = await _pump(tester, api);
    Iterable<int> offsets() =>
        api.chatChannelThreadPagesRequested.map((request) => request.offset);
    expect(offsets(), [0]);

    pages.remove(firstPage);
    await controller.pluginSession
        .require(chatShellService)
        .hydratePluginRoute(_site, ChatPlugin.myThreadsRouteId, force: true);
    await tester.pumpAndSettle();
    expect(offsets(), [0, 0]);
    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Could not load this channel’s threads.'), findsOneWidget);

    pages[firstPage] = ChatThreadPage(threads: [_thread(2), _thread(1)]);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(offsets(), [0, 0, 0]);
    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Could not load this channel’s threads.'), findsNothing);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('reopening the directory adds new threads to a held channel', (
    tester,
  ) async {
    final firstPage = FakeDiscourseApi.chatChannelThreadPageKey(9, 0);
    final pages = {
      firstPage: ChatThreadPage(threads: [_thread(1)], hasMore: true),
      FakeDiscourseApi.chatChannelThreadPageKey(9, 1): ChatThreadPage(
        threads: [_thread(2)],
      ),
    };
    final api = FakeDiscourseApi(
      user: _user,
      chatBrowsePagesByKey: _browsePages,
      chatChannelThreadPagesByKey: pages,
    );
    final controller = await _pump(tester, api);
    Iterable<int> offsets() =>
        api.chatChannelThreadPagesRequested.map((request) => request.offset);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(offsets(), [0, 1]);
    expect(find.text('Thread 2'), findsOneWidget);

    await _mount(tester, controller, shown: false);
    pages[firstPage] = ChatThreadPage(
      threads: [_thread(3), _thread(1)],
      hasMore: true,
    );
    await _mount(tester, controller);
    await tester.pumpAndSettle();

    expect(offsets(), [0, 1, 0]);
    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Thread 3'), findsOneWidget);
  });

  testWidgets('a selected channel pages its own threads, not the directory', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: _user,
      chatBrowsePagesByKey: {
        FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
          channels: [_general],
          hasMore: true,
        ),
      },
      chatChannelThreadPagesByKey: _generalPages(),
    );
    await _pump(tester, api);
    await _selectChannel(tester, 'general');
    expect(find.text('Load more'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(_threadPages(api), [(9, 0), (9, 0), (9, 1)]);
    expect(api.chatBrowseRequested.map((request) => request.offset), [0, 0]);
    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);

    await _selectChannel(tester, 'All channels');
    expect(find.text('Load more'), findsOneWidget);
  });

  testWidgets('a selected channel leaves out another channel’s failed load', (
    tester,
  ) async {
    final api = FakeDiscourseApi(
      user: _user,
      chatBrowsePagesByKey: {
        FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
          channels: [
            _general,
            ChatChannel(
              id: 10,
              title: 'design',
              kind: ChatChannelKind.category,
              threadingEnabled: true,
            ),
          ],
        ),
      },
      chatChannelThreadPagesByKey: _generalPages(),
    );
    await _pump(tester, api);
    expect(_threadPages(api), [(9, 0), (10, 0)]);
    expect(find.text('Could not load this channel’s threads.'), findsOneWidget);

    await _selectChannel(tester, 'general');
    expect(find.text('Could not load this channel’s threads.'), findsNothing);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(_threadPages(api), [(9, 0), (10, 0), (9, 0), (9, 1)]);
    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);

    await _selectChannel(tester, 'All channels');
    expect(find.text('Could not load this channel’s threads.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

const _general = ChatChannel(
  id: 9,
  title: 'general',
  kind: ChatChannelKind.category,
  threadingEnabled: true,
);

final _browsePages = {
  FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
    channels: [_general],
  ),
};

/// Two pages of channel 9's threads, the first reporting more.
Map<String, ChatThreadPage> _generalPages() => {
  FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
    threads: [_thread(1)],
    hasMore: true,
  ),
  FakeDiscourseApi.chatChannelThreadPageKey(9, 1): ChatThreadPage(
    threads: [_thread(2)],
  ),
};

Iterable<(int, int)> _threadPages(FakeDiscourseApi api) => api
    .chatChannelThreadPagesRequested
    .map((request) => (request.channelId, request.offset));

Future<void> _selectChannel(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('chat-threads-channel-filter')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(DCommandList<int>),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

ChatThread _thread(int id) => ChatThread(
  id: id,
  channelId: 9,
  status: 'open',
  replyCount: 1,
  title: 'Thread $id',
  originalMessage: ChatThreadOriginalMessage(
    id: id * 10,
    channelId: 9,
    author: const ChatMessageAuthor(id: 2, username: 'sam'),
    excerpt: 'Original $id',
  ),
);

Future<ShellController> _pump(WidgetTester tester, FakeDiscourseApi api) async {
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await _mount(tester, controller);
  await tester.pumpAndSettle();
  return controller;
}

/// Mounts the thread directory under [controller], or unmounts it while
/// keeping the controller's chat state.
Future<void> _mount(
  WidgetTester tester,
  ShellController controller, {
  bool shown = true,
}) => tester.pumpWidget(
  ShellScope(
    controller: controller,
    child: PluginUiScope.own(
      chatPluginId,
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: shown
              ? const ChatMyThreadsView(siteUrl: _site)
              : const SizedBox.shrink(),
        ),
      ),
    ),
  ),
);

class _ChannelLookupApi extends FakeDiscourseApi {
  _ChannelLookupApi({
    super.user,
    super.chatBrowsePagesByKey,
    super.chatChannelThreadPagesByKey,
  });
  Completer<void>? browseGate;

  @override
  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  }) async {
    await browseGate?.future;
    return super.browseChatChannels(
      siteUrl: siteUrl,
      apiKey: apiKey,
      filter: filter,
      status: status,
      offset: offset,
      limit: limit,
      clientId: clientId,
    );
  }
}
