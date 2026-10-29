import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_navigation.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_threads_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_channels_view.dart';
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
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/skeleton_expectations.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader', hidePresence: false);
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
  setUpAll(() async {
    await (FontLoader(
      'Open Sans',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final view in [
      'chats',
      'channels',
      'joined',
      'threads',
      'channel threads',
    ]) {
      for (final empty in [false, true]) {
        testWidgets('pull refreshes $view with empty=$empty on ${platform.name}', (
          tester,
        ) async {
          final fixture = await _pump(
            tester,
            platform: platform,
            size: const Size(430, 932),
          );
          final api = fixture.api;
          if (empty) {
            api.chatChannelsBySite[_site] = const ChatChannels();
            api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey()] =
                const ChatChannelBrowsePage(channels: []);
            for (final id in [1, 2]) {
              api.chatChannelThreadPagesByKey[FakeDiscourseApi.chatChannelThreadPageKey(
                id,
                0,
              )] = const ChatThreadPage(
                threads: [],
              );
            }
            if (view == 'chats' || view == 'joined') {
              await fixture.chat.loadChannels(_site, force: true);
            }
          }
          switch (view) {
            case 'chats':
              break;
            case 'channels':
              await _tab(tester, ChatBrowsePage.channels);
            case 'joined':
              await fixture.show(
                const ChatChannelsView(
                  siteUrl: _site,
                  kind: ChatChannelListKind.channels,
                ),
              );
            case 'threads':
              await _tab(tester, ChatBrowsePage.threads);
            case 'channel threads':
              await fixture.show(
                const ChatChannelThreadsView(siteUrl: _site, channelId: 1),
              );
          }
          await tester.pumpAndSettle();
          const title = 'Arrived after pulling';
          final channel = _channel(
            view == 'threads' || view == 'channel threads' ? 1 : 3,
            title,
          );
          api.chatChannelsBySite[_site] = ChatChannels(public: [channel]);
          api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey()] =
              ChatChannelBrowsePage(channels: [channel]);
          api.chatChannelThreadPagesByKey[FakeDiscourseApi.chatChannelThreadPageKey(
            1,
            0,
          )] = const ChatThreadPage(
            threads: [
              ChatThread(
                id: 99,
                channelId: 1,
                title: title,
                status: 'open',
                lastMessageId: 199,
                replyCount: 1,
              ),
            ],
          );
          expect(find.text(title), findsNothing);
          final requests =
              api.chatChannelsRequested.length +
              api.chatBrowseRequested.length +
              api.chatChannelThreadPagesRequested.length;
          await tester.drag(find.byType(DPullToRefresh), const Offset(0, 420));
          await tester.pumpAndSettle();
          expect(
            api.chatChannelsRequested.length +
                api.chatBrowseRequested.length +
                api.chatChannelThreadPagesRequested.length,
            greaterThan(requests),
          );
          expect(find.text(title), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final page in ChatBrowsePage.values) {
    testWidgets('repeated pulls wait for the pending ${page.name} refresh', (
      tester,
    ) async {
      final fixture = await _pump(
        tester,
        platform: TargetPlatform.iOS,
        size: const Size(430, 932),
      );
      await _tab(tester, page);
      final api = fixture.api;
      final before = page == ChatBrowsePage.chats
          ? api.chatChannelsRequested.length
          : api.chatBrowseRequested.length;
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      if (page == ChatBrowsePage.chats) {
        api.channelsGate = gate;
      } else {
        api.browseGate = gate;
      }
      await tester.drag(find.byType(DPullToRefresh), const Offset(0, 420));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DSpinner), findsOneWidget);
      await tester.drag(find.byType(DPullToRefresh), const Offset(0, 420));
      await tester.pump(const Duration(milliseconds: 300));
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        page == ChatBrowsePage.chats
            ? api.chatChannelsRequested.length
            : api.chatBrowseRequested.length,
        before + 1,
      );
      expect(find.byType(DSpinner), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  {
    testWidgets(
      'chat directory filters omit headings and close buttons with flat',
      (tester) async {
        final mobile = defaultTargetPlatform != TargetPlatform.macOS;
        final fixture = await _pump(
          tester,
          size: mobile ? const Size(430, 932) : const Size(900, 650),
          platform: defaultTargetPlatform,
          safeArea: mobile
              ? const EdgeInsets.only(top: 47, bottom: 34)
              : EdgeInsets.zero,
        );
        final provider = _Rooms();
        addTearDown(fixture.rooms.attach(provider));
        addTearDown(provider.dispose);
        await tester.pumpAndSettle();

        await _capture(tester, 'chat-filters');
        final activity = tester.getRect(
          find.byKey(const ValueKey('chat-inbox-activity-filter')),
        );
        for (final key in ['chat-inbox-sort-filter']) {
          final control = tester.getRect(find.byKey(ValueKey(key)));
          expect(control.height, activity.height, reason: key);
          expect(control.center.dy, activity.center.dy, reason: key);
        }

        await tester.tap(
          find.byKey(const ValueKey('chat-inbox-activity-filter')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsOneWidget);
        expect(find.text('Chat activity'), findsNothing);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.byType(DDropdownMenuContent), findsNothing);

        await _pick(tester, 'chat-inbox-activity-filter', 'Unread');
        expect(fixture.chat.inboxFilters.filterFor(_site).unreadOnly, isTrue);
        await _pick(tester, 'chat-inbox-activity-filter', 'Recent');
        expect(fixture.chat.inboxFilters.filterFor(_site).unreadOnly, isFalse);
        for (final (sort, label) in [
          (ChatInboxSort.newest, 'Newest'),
          (ChatInboxSort.byType, 'By type'),
        ]) {
          await _pick(tester, 'chat-inbox-sort-filter', label);
          expect(fixture.chat.inboxFilters.filterFor(_site).sort, sort);
        }
        expect(find.byKey(const ValueKey('user-presence-menu')), findsNothing);

        await _tab(tester, ChatBrowsePage.channels);
        await _pick(tester, 'chat-browse-status', 'Closed');
        expect(
          fixture.api.chatBrowseRequested.last.status,
          ChatChannelBrowseStatus.closed,
        );
        await _pick(tester, 'chat-browse-joined', 'Joined');
        expect(
          fixture.chat.inboxFilters.browseFor(_site).membership,
          ChatChannelJoinedFilter.joined,
        );
        await _tab(tester, ChatBrowsePage.threads);
        final navigation = tester.getRect(
          find.byKey(const ValueKey('chat-inbox-back')),
        );
        final channelFilter = tester.getRect(
          find.byKey(const ValueKey('chat-threads-channel-filter')),
        );
        expect(channelFilter.center.dy, navigation.center.dy);
        expect(channelFilter.left, greaterThan(navigation.right));
        await _pick(tester, 'chat-threads-channel-filter', 'general');
        expect(fixture.chat.inboxFilters.browseFor(_site).threadChannelId, 1);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }

  testWidgets(
    'channel membership sheet floats above the safe area and dismisses on touch',
    (tester) async {
      await _pump(
        tester,
        size: const Size(430, 932),
        platform: defaultTargetPlatform,
        safeArea: const EdgeInsets.only(top: 47, bottom: 34),
      );
      await _tab(tester, ChatBrowsePage.channels);

      Future<void> open() async {
        await tester.tap(find.byKey(const ValueKey('chat-browse-joined')));
        await tester.pumpAndSettle();
        _expectMenuPresentation(tester, mobile: true);
        expect(
          tester
              .widget<DSheetContent>(find.byType(DSheetContent))
              .semanticLabel,
          'Membership',
        );
      }

      await open();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      await open();
      await tester.drag(
        find.byKey(const ValueKey('sheet-drag-handle')),
        const Offset(0, 300),
        kind: ui.PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DSheetContent), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  {
    testWidgets(
      'standalone presence menu uses an inset mobile sheet',
      (tester) async {
        final mobile = defaultTargetPlatform != TargetPlatform.macOS;
        final fixture = await _pump(
          tester,
          size: mobile ? const Size(430, 932) : const Size(900, 650),
          platform: defaultTargetPlatform,
          safeArea: mobile
              ? const EdgeInsets.only(top: 47, bottom: 34)
              : EdgeInsets.zero,
        );
        await fixture.show(
          const Align(
            alignment: Alignment.topRight,
            child: UserPresenceMenu(siteUrl: _site),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('user-presence-menu')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('pause-notifications-row')),
          findsOneWidget,
        );
        _expectMenuPresentation(tester, mobile: mobile);
        await _capture(tester, 'status');
        if (mobile) {
          await tester.drag(
            find.byKey(const ValueKey('sheet-drag-handle')),
            const Offset(0, 400),
          );
        } else {
          await tester.tapAt(const Offset(10, 300));
        }
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsNothing);
        expect(find.byType(DDropdownMenuContent), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }

  for (final width in [320.0, 430.0, 900.0]) {
    for (final page in ChatBrowsePage.values) {
      testWidgets(
        page == ChatBrowsePage.channels
            ? 'channels cards align with the filters at width $width'
            : '${page.name} content aligns with its dividers at width $width',
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
          if (page == ChatBrowsePage.channels) {
            final controls = tester.getRect(
              find.byKey(const ValueKey('chat-browse-controls')),
            );
            final card = tester.getRect(
              find.byKey(const ValueKey('chat-browse-channel-1')),
            );
            expect(card.left, closeTo(controls.left, .01));
            expect(card.right, lessThanOrEqualTo(controls.right + .01));
            expect(tester.takeException(), isNull);
            return;
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
            final heading = tester.getRect(
              find.descendant(
                of: find.byKey(
                  const ValueKey('chat-inbox-voice-rooms-heading'),
                ),
                matching: find.text('Voice rooms'),
              ),
            );
            expect(
              heading.left,
              closeTo(_rowContentBounds(tester, row).left, .01),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final (width, platform) in [
    (320.0, TargetPlatform.iOS),
    (430.0, TargetPlatform.iOS),
    (900.0, TargetPlatform.macOS),
  ]) {
    testWidgets('inbox filters and navigation cards fit at width $width', (
      tester,
    ) async {
      await _pump(tester, size: Size(width, 800), platform: platform);
      final title = tester.getRect(
        find.byKey(const ValueKey('chat-inbox-title')),
      );
      final activity = tester.getRect(
        find.byKey(const ValueKey('chat-inbox-activity-filter')),
      );
      final sort = tester.getRect(
        find.byKey(const ValueKey('chat-inbox-sort-filter')),
      );
      final cards = tester.getRect(
        find.byKey(const ValueKey('chat-inbox-navigation')),
      );
      expect(activity.top, greaterThan(title.bottom));
      expect(sort.left, greaterThan(activity.right));
      expect(sort.center.dy, activity.center.dy);
      expect(cards.top, greaterThan(activity.bottom));
      expect(find.byType(DToggleGroup<ChatBrowsePage>), findsNothing);
      expect(find.byKey(const ValueKey('user-presence-menu')), findsNothing);
      expect(find.text('2 joined'), findsOneWidget);
      expect(find.text('2 threads'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('grouping menu offers By type and Newest', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('chat-inbox-sort-filter')));
    await tester.pumpAndSettle();
    final menu = find.byType(DDropdownMenuContent);
    expect(
      find.descendant(of: menu, matching: find.text('By type')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Newest')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: menu, matching: find.text('Direct messages')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

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
          await _tab(tester, page, settle: false);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final skeleton = find.byKey(
          ValueKey('chat-browse-${page.name}-skeleton'),
        );
        expect(skeleton, findsOneWidget);
        expect(find.byType(DSpinner), findsNothing);
        expect(
          find.byKey(
            ValueKey(
              page == ChatBrowsePage.chats
                  ? 'chat-inbox-activity-filter'
                  : 'chat-inbox-back',
            ),
          ),
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
        if (page == ChatBrowsePage.channels) {
          final card = find
              .descendant(of: skeleton, matching: find.byType(DPlaceCard))
              .first;
          expect(tester.getRect(card).left, tester.getRect(skeleton).left);
          gate.complete();
          await tester.pumpAndSettle();
          expect(skeleton, findsNothing);
          expect(tester.takeException(), isNull);
          return;
        }
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
    'inbox cards open directories and retain filters across return navigation',
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
      expect(
        find.descendant(
          of: find.byType(DPageSurface),
          matching: find.text('Threads'),
        ),
        findsOneWidget,
      );
      await _pick(tester, 'chat-threads-channel-filter', 'general');
      expect(find.text('First thread'), findsOneWidget);
      expect(find.text('Second thread'), findsNothing);
      await _tab(tester, ChatBrowsePage.chats);
      expect(find.byKey(const ValueKey('chat-inbox-title')), findsOneWidget);
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
      expect(_unreadOn(1), findsOneWidget);
      expect(_unreadOn(2, '3'), findsOneWidget);
      final browseRequests = fixture.api.chatBrowseRequested.length;
      expect(browseRequests, greaterThan(0));
      fixture.api.chatChannelsBySite[_site] = ChatChannels(
        public: [_channel(1, 'general'), _channel(2, 'workshop', unread: 4)],
      );
      await fixture.chat.loadChannels(_site, force: true);
      await tester.pumpAndSettle();
      expect(_unreadOn(1), findsNothing);
      expect(_unreadOn(2, '4'), findsOneWidget);
      expect(fixture.api.chatBrowseRequested, hasLength(browseRequests));
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
    expect(find.text('general'), findsOneWidget);
    expect(find.text('Voice rooms'), findsOneWidget);
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

  testWidgets('sidebar and inbox share grouping and real star actions', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    expect(find.text('Channels'), findsNWidgets(2));
    expect(find.text('Starred'), findsNothing);
    fixture.api.chatChannelsBySite[_site] = ChatChannels(
      public: [
        _channel(1, 'general', unread: 1),
        _channel(2, 'workshop', unread: 3),
      ],
      direct: [
        ChatChannel(
          id: 3,
          title: 'Ada',
          kind: ChatChannelKind.directMessage,
          membership: const ChatMembership(following: true),
          lastMessageId: 303,
          lastMessageAt: DateTime.now().add(const Duration(minutes: 1)),
          lastMessagePreview: 'See you at the planning session.',
        ),
      ],
    );
    await fixture.chat.loadChannels(_site, force: true);
    final provider = _Rooms();
    addTearDown(fixture.rooms.attach(provider));
    addTearDown(provider.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 650));
    await fixture.show(_sidebarInbox());
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('general')));
    await tester.pumpAndSettle();
    await _capture(tester, 'sidebar-hover');
    await tester.tap(find.byKey(const ValueKey('chat-channel-menu-button-1')));
    await mouse.removePointer();
    await tester.pumpAndSettle();
    await _capture(tester, 'star-menu');
    await tester.tap(find.byKey(const ValueKey('chat-channel-menu-star-1')));
    await tester.pumpAndSettle();
    expect(fixture.api.chatChannelStarsUpdated, [
      (channelId: 1, starred: true),
    ]);
    expect(find.text('Starred'), findsOneWidget);
    expect(find.text('general'), findsOneWidget);
    await _capture(tester, 'sidebar-by-type');
    await _pick(tester, 'chat-inbox-sort-filter', 'Newest');
    expect(find.text('All chats'), findsOneWidget);
    expect(find.text('Starred'), findsNothing);
    await _capture(tester, 'sidebar-newest');
    await tester.binding.setSurfaceSize(const Size(900, 650));
    await fixture.show(const ChatMobileSidebar(siteUrl: _site));
    expect(find.text('All chats'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Ada')).dy,
      lessThan(tester.getTopLeft(find.text('general')).dy),
    );
    await _capture(tester, 'inbox-newest');
    await _pick(tester, 'chat-inbox-sort-filter', 'By type');
    expect(find.text('Starred'), findsOneWidget);
    expect(find.text('general'), findsOneWidget);
    await _capture(tester, 'inbox-by-type');
    await tester.tap(find.byKey(const ValueKey('chat-inbox-channels-card')));
    await tester.pumpAndSettle();
    expect(fixture.shell.currentContent?.id, ChatPlugin.browseRouteId);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sidebar keyboard context menu unstars through the server action',
    (tester) async {
      final fixture = await _pump(tester);
      await fixture.chat.updateChannelStarred(_site, 1, true);
      await fixture.show(_sidebarInbox());
      await tester.tap(find.byKey(const ValueKey('chat-inbox-channel-1')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-channel-menu-star-1')),
        findsOneWidget,
      );
      await _capture(tester, 'keyboard-star-menu');
      await tester.tap(find.byKey(const ValueKey('chat-channel-menu-star-1')));
      await tester.pumpAndSettle();
      expect(fixture.api.chatChannelStarsUpdated, [
        (channelId: 1, starred: true),
        (channelId: 1, starred: false),
      ]);
      expect(find.text('Starred'), findsNothing);
      expect(find.text('general'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('thread card marks a paginated count as a lower bound', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    fixture.api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey()] =
        ChatChannelBrowsePage(
          channels: [_channel(1, 'general'), _channel(2, 'workshop')],
          hasMore: true,
        );
    await fixture.show(const ChatInboxNavigation(siteUrl: _site));
    expect(find.text('2+ threads'), findsOneWidget);
    expect(find.text('2 threads'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone inbox grouping and long press preserve safe areas', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      platform: TargetPlatform.iOS,
      size: const Size(430, 932),
      safeArea: const EdgeInsets.only(top: 47, bottom: 34),
    );
    final provider = _Rooms();
    addTearDown(fixture.rooms.attach(provider));
    addTearDown(provider.dispose);
    await fixture.show(
      const SafeArea(child: ChatMobileSidebar(siteUrl: _site)),
    );
    await tester.longPress(find.byKey(const ValueKey('chat-inbox-channel-1')));
    await tester.pumpAndSettle();
    await _capture(tester, 'phone-star-menu');
    await tester.tap(find.byKey(const ValueKey('chat-channel-menu-star-1')));
    await tester.pumpAndSettle();
    expect(fixture.api.chatChannelStarsUpdated, [
      (channelId: 1, starred: true),
    ]);
    expect(find.text('Starred'), findsOneWidget);
    await _capture(tester, 'phone-by-type');
    await _pick(tester, 'chat-inbox-sort-filter', 'Newest');
    expect(find.text('All chats'), findsOneWidget);
    await _capture(tester, 'phone-newest');
    expect(tester.takeException(), isNull);
  });

  testWidgets('fixed inbox filters preserve the continuous sidebar canvas', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    const canvas = Color(0xff153d99);
    {
      await fixture.show(
        Theme(
          data: AppTheme.forBrightness(
            Brightness.dark,
            background: const ForumBackground.appearance(transparency: .2),
          ).copyWith(platform: TargetPlatform.macOS),
          child: Center(
            child: SizedBox(
              width: 500,
              height: 220,
              child: RepaintBoundary(
                key: const ValueKey('inbox-filter-canvas'),
                child: ForumWindowBackground(
                  child: ColoredBox(
                    color: canvas,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _sidebarInbox(
                        trailingSlivers: const [
                          SliverToBoxAdapter(child: SizedBox(height: 800)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final viewport = find.descendant(
        of: find.byKey(const ValueKey('inbox-filter-canvas')),
        matching: find.byType(CustomScrollView),
      );
      final scroll = tester.widget<CustomScrollView>(viewport).controller!;
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(ChatInboxFilterBar));
      final kind = tester.getRect(
        find.byKey(const ValueKey('chat-inbox-sort-filter')),
      );

      final capture = find.byKey(const ValueKey('inbox-filter-canvas'));
      final gap =
          Offset(kind.right + 8, bar.center.dy) - tester.getTopLeft(capture);
      final pixels = await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(capture)
            .toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (gap.dy.floor() * image.width + gap.dx.floor()) * 4;
        final pixel = bytes.buffer.asUint8List(offset, 4).toList();
        image.dispose();
        return pixel;
      });
      expect(pixels, [0x15, 0x3d, 0x99, 0xff], reason: 'flat');
      scroll.jumpTo(60);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ChatInboxFilterBar)), bar);
      expect(tester.takeException(), isNull);
    }
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

Widget _sidebarInbox({List<Widget> trailingSlivers = const []}) => Builder(
  builder: (context) {
    final section = const ChatPlugin()
        .sidebarSections(context)
        .singleWhere((section) => section.id == 'chat-inbox');
    return DSidebarContent.slivers(
      header: Builder(builder: section.pinnedHeaderBuilder!),
      slivers: [
        Builder(builder: section.bodyBuilder!),
        ...trailingSlivers,
      ],
    );
  },
);

Finder _unreadOn(int channelId, [String count = '1']) => find.descendant(
  of: find.byKey(ValueKey('chat-browse-channel-$channelId')),
  matching: find.text(count),
);

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

Future<void> _tab(
  WidgetTester tester,
  ChatBrowsePage page, {
  bool settle = true,
}) async {
  final back = find.byKey(const ValueKey('chat-inbox-back'));
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back);
    await tester.pumpAndSettle();
  }
  if (page == ChatBrowsePage.chats) return;
  final target = find.byKey(
    ValueKey(
      page == ChatBrowsePage.channels
          ? 'chat-inbox-channels-card'
          : 'chat-inbox-threads-card',
    ),
  );
  await tester.ensureVisible(target);
  await tester.tap(target);
  if (settle) await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String key, String value) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  final mobile = switch (Theme.of(
    tester.element(find.byKey(ValueKey(key))),
  ).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };
  _expectMenuPresentation(tester, mobile: mobile);
  if (mobile) {
    final label = switch (key) {
      'chat-inbox-sort-filter' => 'Chat order',
      'chat-inbox-activity-filter' => 'Chat activity',
      'chat-browse-status' => 'Status',
      'chat-browse-joined' => 'Membership',
      'chat-threads-channel-filter' => 'Channel',
      _ => throw StateError('Unknown chat filter: $key'),
    };
    expect(
      find.descendant(
        of: find.byType(DSheetContent),
        matching: find.text(label),
      ),
      findsNothing,
    );
    expect(
      tester.widget<DSheetContent>(find.byType(DSheetContent)).semanticLabel,
      label,
    );
  }
  final channel = key == 'chat-threads-channel-filter';
  expect(
    channel
        ? find.byType(DCommandList<int>)
        : find.byType(DDropdownMenuContent),
    findsOneWidget,
  );
  if (channel &&
      find
          .descendant(
            of: find.byType(DCommandList<int>),
            matching: find.text(value),
          )
          .evaluate()
          .isEmpty) {
    await tester.tap(
      find.descendant(
        of: find.byType(DCommandList<int>),
        matching: find.text('Load more'),
      ),
    );
    await tester.pumpAndSettle();
  }
  await _capture(tester, key);
  await tester.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (channel || widget.properties.inMutuallyExclusiveGroup == true) &&
          widget.properties.label == value,
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(DSheetContent), findsNothing);
  expect(find.byType(DDropdownMenuContent), findsNothing);
}

void _expectMenuPresentation(WidgetTester tester, {required bool mobile}) {
  final sheet = find.byType(DSheetContent);
  expect(sheet, mobile ? findsOneWidget : findsNothing);
  if (!mobile) return;

  expect(tester.widget<DSheetContent>(sheet).side, DSheetSide.bottom);
  expect(find.byKey(const ValueKey('sheet-drag-handle')), findsOneWidget);
  expect(find.byType(DSheetHeader), findsNothing);
  expect(find.byTooltip('Close'), findsNothing);
  expect(tester.widget<DSheetContent>(sheet).showCloseButton, isFalse);
  final viewport = tester.getRect(
    find.byKey(const ValueKey('chat-browse-render')),
  );
  final bounds = tester.getRect(sheet);
  final media = MediaQuery.of(tester.element(sheet));
  final safeBottom =
      tester.view.viewPadding.bottom / tester.view.devicePixelRatio;
  final dock = DMobileDockGeometry(foot: safeBottom);
  expect(bounds.left - viewport.left, 0);
  expect(viewport.right - bounds.right, 0);
  expect(viewport.bottom - bounds.bottom, closeTo(dock.endLift, .01));
  expect(bounds.top, greaterThanOrEqualTo(viewport.top + media.padding.top));
}

Future<void> _capture(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('CHAT_HEADER_CAPTURE_DIR');
  if (directory.isEmpty) return;
  final context = tester.element(
    find.byKey(const ValueKey('chat-browse-render')),
  );
  final platform = Theme.of(
    tester.element(find.byType(Scaffold).first),
  ).platform;

  await tester.runAsync(() async {
    final image = await (context.findRenderObject()! as RenderRepaintBoundary)
        .toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name-${platform.name}-flat.png',
    ).writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
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
  EdgeInsets safeArea = EdgeInsets.zero,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final pixelRatio = tester.view.devicePixelRatio;
  tester.view.viewPadding = FakeViewPadding(
    top: safeArea.top * pixelRatio,
    bottom: safeArea.bottom * pixelRatio,
  );
  tester.view.padding = FakeViewPadding(
    top: safeArea.top * pixelRatio,
    bottom: safeArea.bottom * pixelRatio,
  );
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
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
          RepaintBoundary(
            key: const ValueKey('chat-browse-render'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.forBrightness(
                Brightness.dark,
                fontFamily: 'Open Sans',
              ).copyWith(platform: platform),
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
