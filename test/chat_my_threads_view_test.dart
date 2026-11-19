import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_ui_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
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
import 'support/native_ui_evidence.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('the channel pill opens the panel to pick from on $platform', (
      tester,
    ) async {
      final phone = platform == TargetPlatform.iOS;
      tester.view.physicalSize = phone
          ? const Size(390, 844)
          : const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await prepareNativeUiEvidence(tester);
      const design = ChatChannel(
        id: 10,
        title: 'design',
        kind: ChatChannelKind.category,
        threadingEnabled: true,
        categoryColor: Color(0xFF0E76BD),
        membership: ChatMembership(following: true),
      );
      const quiet = ChatChannel(
        id: 12,
        title: 'quiet',
        kind: ChatChannelKind.category,
        membership: ChatMembership(following: true),
      );
      const empty = ChatChannel(
        id: 11,
        title: 'empty channel',
        kind: ChatChannelKind.category,
        threadingEnabled: true,
      );
      final api = FakeDiscourseApi(
        user: _user,
        chatChannelsBySite: {
          _site: const ChatChannels(public: [design, quiet]),
        },
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
            channels: [_general, design, empty],
          ),
        },
        chatChannelThreadPagesByKey: {
          FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
            threads: [_thread(1)],
          ),
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
      await _pump(tester, api, loadChannels: true);
      expect(find.text('Thread 1'), findsOneWidget);
      expect(find.text('Design thread'), findsOneWidget);
      final browsed = api.chatBrowseRequested.length;

      await tester.tap(_pill);
      await tester.pumpAndSettle();
      expect(
        find.byType(phone ? DSheetContent : DDialogContent),
        findsOneWidget,
      );
      expect(
        find.text('Channel'),
        phone ? findsOneWidget : findsNWidgets(2),
        reason: 'The pill says it; a desktop panel is titled by it too',
      );
      expect(find.text('Find a channel'), findsOneWidget);
      expect(_names(tester), ['All channels', 'design', 'general']);
      expect(
        _option('general'),
        findsOneWidget,
        reason: 'Left, but its thread is still the reader\'s to reach',
      );
      expect(_option('quiet'), findsNothing, reason: 'Threads are off');
      expect(_option('empty channel'), findsNothing, reason: 'Not theirs');
      expect(_picked(tester, 'All channels'), isTrue);
      expect(_picked(tester, 'design'), isFalse);
      expect(_checks, findsOneWidget);
      final mark = tester.widget<DIcon>(
        find.descendant(
          of: _row('design'),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.hashtag,
          ),
        ),
      );
      expect(mark.color, const Color(0xFF0E76BD));
      expect(find.text('Join'), findsNothing);
      expect(find.text('Not joined'), findsNothing, reason: 'No chips');
      expect(find.textContaining('member'), findsNothing);
      await captureNativeUi(
        tester,
        'channel-panel-pick-${phone ? 'phone' : 'desktop'}',
      );

      await tester.enterText(_field, 'DES');
      await tester.pumpAndSettle();
      expect(_names(tester), ['design']);
      await tester.enterText(_field, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No channels match “zzz”'), findsOneWidget);
      expect(
        api.chatBrowseRequested,
        hasLength(browsed),
        reason: 'Found among what is listed, with no request',
      );
      await tester.enterText(_field, '');
      await tester.pumpAndSettle();

      await tester.tap(_option('design'));
      await tester.pumpAndSettle();
      expect(_field, findsNothing, reason: 'The one pressed is the choice');
      expect(find.text('Design thread'), findsOneWidget);
      expect(find.text('Thread 1'), findsNothing);
      expect(
        find.descendant(of: _pill, matching: find.text('design')),
        findsOneWidget,
      );

      await tester.tap(_pill);
      await tester.pumpAndSettle();
      expect(_names(tester), ['All channels', 'design', 'general']);
      expect(_picked(tester, 'design'), isTrue);
      expect(_picked(tester, 'All channels'), isFalse);
      expect(
        find.descendant(of: _row('design'), matching: _checks),
        findsOneWidget,
      );
      await tester.tap(_option('general'));
      await tester.pumpAndSettle();
      expect(find.text('Thread 1'), findsOneWidget);
      expect(find.text('Design thread'), findsNothing);

      await _selectChannel(tester, 'All channels');
      expect(find.text('Thread 1'), findsOneWidget);
      expect(find.text('Design thread'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('the channel picked is kept while the page is away', (
    tester,
  ) async {
    const design = ChatChannel(
      id: 10,
      title: 'design',
      kind: ChatChannelKind.category,
      threadingEnabled: true,
      membership: ChatMembership(following: true),
    );
    final api = FakeDiscourseApi(
      user: _user,
      chatChannelsBySite: {
        _site: const ChatChannels(public: [design]),
      },
      chatBrowsePagesByKey: {
        FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
          channels: [_general, design],
        ),
      },
      chatChannelThreadPagesByKey: {
        FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
          threads: [_thread(1)],
        ),
        FakeDiscourseApi.chatChannelThreadPageKey(10, 0): const ChatThreadPage(
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
      },
    );
    final controller = await _pump(tester, api, loadChannels: true);
    await _selectChannel(tester, 'design');
    expect(_threadPages(api), [(9, 0), (10, 0), (10, 0)]);

    final reads = api.chatBrowseRequested.length;
    await _mount(tester, controller, shown: false);
    await _mount(tester, controller);
    await tester.pumpAndSettle();
    expect(api.chatBrowseRequested, hasLength(reads));
    expect(find.text('Design thread'), findsOneWidget);
    expect(find.text('Thread 1'), findsNothing);
    expect(
      tester
          .widget<ChatThreadChannelFilter>(find.byType(ChatThreadChannelFilter))
          .selected
          ?.id,
      10,
    );
    await controller.pluginSession
        .require(chatShellService)
        .hydratePluginRoute(_site, ChatRoute.myThreadsRouteId, force: true);
    await tester.pumpAndSettle();
    expect(api.chatBrowseRequested, hasLength(reads));
    expect(find.text('Design thread'), findsOneWidget);
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
      expect(tester.widget(badge), isA<DBadge>());
    }
    expect(find.byKey(const ValueKey('chat-my-thread-unread-4')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('threads with new replies lead, newest first across channels', (
    tester,
  ) async {
    const design = ChatChannel(
      id: 10,
      title: 'design',
      kind: ChatChannelKind.category,
      threadingEnabled: true,
    );
    ChatThread thread(int id, int channel, int day, {int unread = 0}) =>
        ChatThread(
          id: id,
          channelId: channel,
          status: 'open',
          title: 'Thread $id',
          replyCount: 1,
          lastMessageId: 100 + day,
          tracking: ChatTracking(unreadCount: unread),
          preview: ChatThreadPreview(
            threadId: id,
            replyCount: 1,
            lastReplyId: 100 + day,
            lastReplyAt: DateTime.utc(2026, 11, day),
          ),
        );
    final api = FakeDiscourseApi(
      user: _user,
      chatBrowsePagesByKey: {
        FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
          channels: [_general, design],
        ),
      },
      chatChannelThreadPagesByKey: {
        FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
          threads: [thread(1, 9, 14, unread: 3), thread(2, 9, 18)],
        ),
        FakeDiscourseApi.chatChannelThreadPageKey(10, 0): ChatThreadPage(
          threads: [thread(3, 10, 15, unread: 1), thread(4, 10, 19)],
        ),
      },
    );
    await prepareNativeUiEvidence(tester);
    await _pump(tester, api);

    final positions = [
      for (final id in [1, 2, 3, 4])
        (id: id, top: tester.getTopLeft(find.text('Thread $id')).dy),
    ]..sort((a, b) => a.top.compareTo(b.top));
    expect(positions.map((row) => row.id), [3, 1, 4, 2]);
    await captureNativeUi(tester, 'threads-by-unread-and-latest-reply');
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
        .hydratePluginRoute(_site, ChatRoute.myThreadsRouteId, force: true);
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
    expect(find.text('Load more'), findsNothing);

    await tester.pumpAndSettle();

    expect(_threadPages(api), [(9, 0), (9, 0), (9, 1)]);
    expect(
      api.chatBrowseRequested.map((request) => request.offset),
      [0, 1],
      reason: 'Picking lists what the page already holds and asks for nothing',
    );
    expect(find.text('Thread 2'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);

    await _selectChannel(tester, 'All channels');
    expect(find.text('Load more'), findsNothing);
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

final _pill = find.byKey(const ValueKey('chat-threads-channel-filter'));
final _field = find.byKey(const ValueKey('chat-channel-panel-field'));
final _list = find.byKey(const ValueKey('chat-channel-panel-list'));
final _checks = find.descendant(
  of: _list,
  matching: find.byWidgetPredicate(
    (widget) => widget is DIcon && widget.icon == DIcons.check,
  ),
);

Finder _row(String name) => find.descendant(
  of: _list,
  matching: find.byWidgetPredicate(
    (widget) => widget is DItem && widget.semanticLabel == name,
  ),
);

Finder _option(String name) =>
    find.descendant(of: _row(name), matching: find.text(name));

bool _picked(WidgetTester tester, String name) =>
    tester.widget<DItem>(_row(name)).selected;

/// The names the panel lists, top to bottom.
List<String?> _names(WidgetTester tester) => [
  for (final item in tester.widgetList<DItem>(
    find.descendant(of: _list, matching: find.byType(DItem)),
  ))
    item.semanticLabel,
];

Future<void> _selectChannel(WidgetTester tester, String label) async {
  await tester.tap(_pill);
  await tester.pumpAndSettle();
  await tester.tap(_option(label));
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

Future<ShellController> _pump(
  WidgetTester tester,
  FakeDiscourseApi api, {
  bool loadChannels = false,
}) async {
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
  if (loadChannels) {
    await controller.pluginSession
        .require(chatControllerService)
        .loadChannels(_site);
  }
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
        builder: nativeUiEvidenceBuilder,
        home: Scaffold(
          body: shown
              ? const ChatMyThreadsView(siteUrl: _site)
              : const SizedBox.shrink(),
        ),
      ),
    ),
  ),
);
