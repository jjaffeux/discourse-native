import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
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

    expect(_threadPages(api), [(9, 0), (9, 1)]);
    expect(api.chatBrowseRequested.map((request) => request.offset), [0]);
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

    expect(_threadPages(api), [(9, 0), (10, 0), (9, 1)]);
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
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.inMutuallyExclusiveGroup == true &&
          widget.properties.label == label,
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
