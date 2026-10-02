import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_navigation.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_rooms.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/skeleton_expectations.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');
final _config = SiteConfig(
  plugins: PluginData.none.withValue(
    chatSettingsDataKey,
    const ChatSettings(
      chatEnabled: true,
      publicChannelsEnabled: true,
      threadsEnabled: true,
    ),
  ),
);

ChatChannel _channel(int id, String name, {int unread = 0}) => ChatChannel(
  id: id,
  title: name,
  kind: ChatChannelKind.category,
  categoryColor: id == 1 ? Colors.amber : Colors.blue,
  membership: const ChatMembership(following: true),
  tracking: ChatTracking(unreadCount: unread),
  threadingEnabled: true,
  lastMessageId: 100 + id,
  lastMessageAt: DateTime.now(),
  lastMessagePreview: 'The latest message',
  lastMessageUsername: 'sam',
  lastMessageUserId: 2,
);

void main() {
  for (final width in [320.0, 430.0, 900.0]) {
    for (final page in ChatBrowsePage.values) {
      testWidgets(
        '${page.name} content aligns with its dividers at width $width',
        (tester) async {
          final fixture = await _pump(
            tester,
            size: Size(width, 800),
            platform: width < 600 ? TargetPlatform.iOS : TargetPlatform.macOS,
          );
          await _tab(tester, page);
          if (page == ChatBrowsePage.chats) {
            final provider = _Rooms();
            final detach = fixture.rooms.attach(provider);
            addTearDown(detach);
            addTearDown(provider.dispose);
            await tester.pumpAndSettle();
          }
          final row = find.byKey(
            ValueKey(switch (page) {
              ChatBrowsePage.chats => 'chat-inbox-channel-1',
              ChatBrowsePage.channels => 'chat-browse-channel-1',
              ChatBrowsePage.threads => 'chat-my-thread-1',
            }),
          );
          final divider = tester.getRect(find.byType(DSeparator).first);
          final inset = width < 600 ? 0.0 : 16.0;
          void expectAligned(Finder row) {
            final bounds = _rowContentBounds(tester, row);
            expect(bounds.left, closeTo(divider.left + inset, .01));
            expect(bounds.right, closeTo(divider.right - inset, .01));
          }

          expectAligned(row);
          if (page == ChatBrowsePage.chats) {
            expectAligned(find.byType(ChatInboxRoomRow).first);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final page in ChatBrowsePage.values) {
    testWidgets(
      '${page.name} shows skeleton rows until its request completes',
      (tester) async {
        final fixture = await _pump(tester, platform: defaultTargetPlatform);
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        Future<void>? request;
        if (page == ChatBrowsePage.chats) {
          fixture.api.channelsGate = gate;
          request = fixture.chat.loadChannels(_site, force: true);
        } else {
          fixture.api.browseGate = gate;
          await tester.tap(find.byKey(ValueKey(('toggle-group-item', page))));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final skeleton = find.byKey(
          ValueKey('chat-browse-${page.name}-skeleton'),
        );
        expect(skeleton, findsOneWidget);
        expect(find.byType(DSpinner), findsNothing);
        expect(
          find.byKey(const ValueKey('chat-browse-navigation')),
          findsOneWidget,
        );
        for (final size in [const Size(430, 932), const Size(900, 1200)]) {
          await tester.binding.setSurfaceSize(size);
          await tester.pump();
          expectSkeletonFillsViewport(
            tester,
            label: 'Loading ${page.name}',
            bottom: size.height - (page == ChatBrowsePage.chats ? 0 : 16),
          );
        }
        await tester.binding.setSurfaceSize(const Size(320, 260));
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final row = find
            .descendant(of: skeleton, matching: find.byType(DItem))
            .first;
        final divider = tester.getRect(
          find
              .descendant(of: skeleton, matching: find.byType(DSeparator))
              .first,
        );
        final bounds = _rowContentBounds(tester, row);
        expect(bounds.left, divider.left);
        expect(bounds.right, divider.right);
        gate.complete();
        await request;
        await tester.pumpAndSettle();
        expect(skeleton, findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }),
    );
  }

  testWidgets(
    'thread browsing paginates channels and includes unjoined threads',
    (tester) async {
      final fixture = await _pump(tester);
      final key = FakeDiscourseApi.chatBrowseKey();
      fixture.api.chatBrowsePagesByKey[key] = ChatChannelBrowsePage(
        channels: fixture.api.chatBrowsePagesByKey[key]!.channels,
        hasMore: true,
      );
      final extra = _channel(
        3,
        'design',
      ).withMembership(const ChatMembership(following: false));
      fixture.api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey(
        offset: 2,
      )] = ChatChannelBrowsePage(
        channels: [extra],
      );
      fixture
          .api
          .chatChannelThreadPagesByKey[FakeDiscourseApi.chatChannelThreadPageKey(
        3,
        0,
      )] = const ChatThreadPage(
        threads: [
          ChatThread(
            id: 3,
            channelId: 3,
            lastMessageId: 103,
            status: 'open',
            title: 'An unfollowed thread',
            replyCount: 2,
          ),
        ],
      );
      await _tab(tester, ChatBrowsePage.threads);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('An unfollowed thread'), findsOneWidget);
      expect(fixture.chat.channel(_site, 3)!.membership.following, isFalse);
      expect(fixture.api.chatThreadPagesRequested, isEmpty);
      await _pick(tester, 'chat-threads-channel-filter', 'design');
      expect(find.text('First thread'), findsNothing);
      expect(find.text('An unfollowed thread'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving from the channel menu keeps the browse page open', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await _tab(tester, ChatBrowsePage.channels);
    await tester.tap(find.byKey(const ValueKey('chat-channel-menu-button-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-channel-menu-leave-1')));
    await tester.pumpAndSettle();
    expect(fixture.shell.currentContent?.id, ChatPlugin.browseRouteId);
    expect(find.byKey(const ValueKey('chat-join-1')), findsOneWidget);
  });

  testWidgets(
    'all three directories navigate as peers and retain their filters',
    (tester) async {
      final fixture = await _pump(tester);
      await _tab(tester, ChatBrowsePage.channels);
      expect(find.text('Browse channels'), findsOneWidget);
      expect(fixture.shell.currentContent?.id, ChatPlugin.browseRouteId);
      await tester.enterText(find.byType(EditableText), 'general');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await _pick(tester, 'chat-browse-status', 'Closed');
      await _pick(tester, 'chat-browse-joined', 'Joined');
      await _tab(tester, ChatBrowsePage.threads);
      expect(find.text('Browse threads'), findsOneWidget);
      await _pick(tester, 'chat-threads-channel-filter', 'general');
      expect(find.text('First thread'), findsOneWidget);
      expect(find.text('Second thread'), findsNothing);
      await _tab(tester, ChatBrowsePage.chats);
      expect(find.text('Browse chats'), findsOneWidget);
      await _tab(tester, ChatBrowsePage.channels);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'general',
      );
      expect(find.text('Closed'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('chat-browse-joined')),
          matching: find.text('Joined'),
        ),
        findsOneWidget,
      );
      await _tab(tester, ChatBrowsePage.threads);
      expect(find.text('First thread'), findsOneWidget);
      expect(find.text('Second thread'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'channel browsing uses live unread tracking without additional requests',
    (tester) async {
      final fixture = await _pump(tester);
      await _tab(tester, ChatBrowsePage.channels);
      expect(find.text('1 unread message'), findsOneWidget);
      expect(find.text('3 unread messages'), findsOneWidget);
      expect(fixture.api.chatBrowseRequested, hasLength(1));
      fixture.api.chatChannelsBySite[_site] = ChatChannels(
        public: [_channel(1, 'general'), _channel(2, 'workshop', unread: 4)],
      );
      await fixture.chat.loadChannels(_site, force: true);
      await tester.pumpAndSettle();
      expect(find.text('No unread messages'), findsOneWidget);
      expect(find.text('4 unread messages'), findsOneWidget);
      expect(fixture.api.chatBrowseRequested, hasLength(1));
    },
  );

  testWidgets(
    'chat preview shows one unread message while the sidebar counts it',
    (tester) async {
      final fixture = await _pump(tester);
      expect(find.text('sam: The latest message'), findsOneWidget);
      expect(find.text('3 messages'), findsOneWidget);
      await fixture.show(
        ChatInboxRow(
          siteUrl: _site,
          channel: _channel(1, 'general', unread: 1),
          compact: true,
          onPressed: () {},
        ),
      );
      expect(find.text('1 message'), findsOneWidget);
      final avatar = tester.widget<DAvatar>(find.byType(DAvatar).first);
      expect(avatar.borderRadius, isNotNull);
    },
  );

  testWidgets('inbox rows announce unread like the channel list', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final semantics = tester.ensureSemantics();
    for (final compact in [false, true]) {
      for (final unread in [0, 1]) {
        await fixture.show(
          ChatInboxRow(
            siteUrl: _site,
            channel: _channel(1, 'general', unread: unread),
            compact: compact,
            onPressed: () {},
          ),
        );
        final label = tester
            .getSemantics(find.byKey(const ValueKey('chat-inbox-channel-1')))
            .label;
        expect(
          label,
          unread > 0
              ? startsWith('Unread conversation\n')
              : isNot(contains('Unread')),
          reason: 'compact: $compact, unread: $unread',
        );
      }
    }
    semantics.dispose();
  });

  testWidgets('voice scope and unread activity filter the same room data', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    final provider = _Rooms();
    final detach = fixture.rooms.attach(provider);
    addTearDown(detach);
    await tester.pumpAndSettle();
    expect(find.text('Watercooler'), findsOneWidget);
    expect(find.text('Quiet room'), findsOneWidget);
    expect(find.text('Empty'), findsNothing);
    expect(find.text('3 people here'), findsNothing);
    await _pick(tester, 'chat-inbox-kind-filter', 'Voice rooms');
    expect(find.text('general'), findsNothing);
    await _pick(tester, 'chat-inbox-activity-filter', 'Unread');
    expect(find.text('Watercooler'), findsOneWidget);
    expect(find.text('Quiet room'), findsNothing);
    await tester.tap(find.text('Watercooler'));
    expect(provider.opened, 1);
    provider.people = 0;
    provider.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Watercooler'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sidebar inbox offers voice rooms once Voice attaches', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await fixture.show(
      const CustomScrollView(slivers: [ChatSidebarInbox(siteUrl: _site)]),
    );
    List<ChatInboxKind?> kinds() => [
      for (final entry
          in tester
              .widget<ChatBrowseFilter<ChatInboxKind>>(
                find.byKey(const ValueKey('chat-inbox-kind-filter')),
              )
              .entries)
        if (entry case DSelectItem(:final value)) value,
    ];
    expect(kinds(), isNot(contains(ChatInboxKind.voiceRooms)));

    // The conversations it lists are unchanged, so only the filters redraw.
    final detach = fixture.rooms.attach(_Rooms());
    addTearDown(detach);
    await tester.pump();

    expect(kinds(), contains(ChatInboxKind.voiceRooms));
    expect(tester.takeException(), isNull);
  });

  testWidgets('thread rows show the latest reply and reply count', (
    tester,
  ) async {
    await _pump(tester);
    await _tab(tester, ChatBrowsePage.threads);
    expect(find.text('A recent answer'), findsNWidgets(2));
    expect(find.text('3 replies'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('chat-my-thread-preview-surface-1')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Rect _rowContentBounds(WidgetTester tester, Finder row) {
  final parts = find.descendant(
    of: row,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DItemMedia ||
          widget is DItemContent ||
          widget is DItemActions,
    ),
  );
  return parts
      .evaluate()
      .map((element) => tester.getRect(find.byWidget(element.widget)))
      .reduce((a, b) => a.expandToInclude(b));
}

Future<void> _tab(WidgetTester tester, ChatBrowsePage page) async {
  final target = find.byKey(ValueKey(('toggle-group-item', page)));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String key, String value) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.inMutuallyExclusiveGroup == true &&
          widget.properties.label == value,
    ),
  );
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture(this.shell, this.chat, this.rooms, this.api, this.show);
  final ShellController shell;
  final ChatController chat;
  final ChatInboxRooms rooms;
  final _GatedApi api;
  final Future<void> Function(Widget) show;
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(900, 650),
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final channels = [
    _channel(1, 'general', unread: 1),
    _channel(2, 'workshop', unread: 3),
  ];
  final api = _GatedApi(
    user: _user,
    totals: chatNotificationTotals(),
    siteConfigs: {_site: _config},
    chatChannelsBySite: {
      _site: ChatChannels(public: channels, hasThreads: true),
    },
    chatBrowsePagesByKey: {
      FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
        channels: channels,
      ),
    },
    chatChannelThreadPagesByKey: {
      for (final id in [1, 2])
        FakeDiscourseApi.chatChannelThreadPageKey(id, 0): ChatThreadPage(
          threads: [
            ChatThread(
              id: id,
              channelId: id,
              lastMessageId: 100 + id,
              status: 'open',
              title: id == 1 ? 'First thread' : 'Second thread',
              replyCount: 3,
              preview: ChatThreadPreview(
                threadId: id,
                replyCount: 3,
                lastReplyExcerpt: 'A recent answer',
                lastReplyUsername: 'sam',
              ),
            ),
          ],
        ),
    },
  );
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user, config: _config),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  late BuildContext scope;
  Future<void> show(Widget? child) async {
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: PluginUiScope.own(
          chatPluginId,
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: platform),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  scope = context;
                  return child ??
                      ListenableBuilder(
                        listenable: shell,
                        builder: (context, _) => shell.currentContent == null
                            ? const ChatMobileSidebar(siteUrl: _site)
                            : const ChatPlugin().content(
                                    context,
                                    shell.currentContent!,
                                  ) ??
                                  const ChatMobileSidebar(siteUrl: _site),
                      );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  await show(null);
  final chat = PluginUiScope.require(scope, chatControllerService);
  await chat.loadChannels(_site);
  PluginUiScope.require(scope, chatShellService).openChats();
  await tester.pumpAndSettle();
  return _Fixture(
    shell,
    chat,
    PluginUiScope.require(scope, chatInboxRoomsService),
    api,
    show,
  );
}

class _Rooms extends ChangeNotifier implements ChatInboxRoomProvider {
  int opened = 0;
  int people = 3;
  @override
  bool available(String siteUrl) => true;
  @override
  List<ChatInboxRoom> rooms(String siteUrl) => [
    ChatInboxRoom(
      id: 1,
      name: 'Watercooler',
      people: people,
      open: (_) async {
        opened++;
      },
    ),
    ChatInboxRoom(
      id: 2,
      name: 'Quiet room',
      people: 0,
      open: (_) async {
        opened++;
      },
    ),
  ];
}

class _GatedApi extends FakeDiscourseApi {
  _GatedApi({
    super.user,
    super.totals,
    super.siteConfigs,
    super.chatChannelsBySite,
    super.chatBrowsePagesByKey,
    super.chatChannelThreadPagesByKey,
  });

  Completer<void>? channelsGate;
  Completer<void>? browseGate;

  @override
  Future<ChatChannels> chatChannels({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    await channelsGate?.future;
    return super.chatChannels(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

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
