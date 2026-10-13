import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_panel_tabs_test.dart' as panels;
import 'support/shell_test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets('Chat destinations open independent tabs and follow focus', (
    tester,
  ) async {
    final shell = await panels.pumpTabs(tester, threads: true, voice: false);
    final forumTab = shell.activeTabId!;
    final directoryTabs = <String>{};
    for (final (label, route) in [
      ('Chats', ChatPlugin.inboxRouteId),
      ('Channels', ChatPlugin.browseRouteId),
      ('Threads', ChatPlugin.myThreadsRouteId),
    ]) {
      if (directoryTabs.isNotEmpty) {
        shell.openContentInNewTab(ContentRoute.newTab());
        await tester.pumpAndSettle();
      }
      await tester.tap(panels.tab('chat'));
      await tester.pumpAndSettle();
      final sourceTab = shell.activeTabId;
      await tester.tap(sidebarDestination(label));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, route);
      expect(shell.activeTabId, isNot(sourceTab));
      directoryTabs.add(shell.activeTabId!);
      expect(
        sidebarDestination('Chats'),
        findsNothing,
        reason: 'the open directory carries its own three-way switch',
      );
      expect(tester.widget<DTabs<String>>(panels.tabs).value, 'chat');
      expect(tester.takeException(), isNull);
    }
    expect(directoryTabs, hasLength(3));
    final tabCount = shell.currentWorkspace!.tabs.length;
    shell.pluginSession.require(chatShellService).openChats(newTab: true);
    await tester.pumpAndSettle();
    expect(shell.currentWorkspace!.tabs.length, tabCount);
    expect(shell.currentContent?.id, ChatPlugin.inboxRouteId);
    shell.selectTab(forumTab);
    await tester.pumpAndSettle();
    expect(tester.widget<DTabs<String>>(panels.tabs).value, 'forum');
    expect(sidebarDestination('Topics'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'Chat links follow conversation and directory focus in either panel',
    (tester) async {
      final shell = await panels.pumpTabs(
        tester,
        threads: true,
        voice: false,
        channelDetails: const {
          9: ChatChannel(
            id: 9,
            title: 'General',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
          ),
        },
      );
      final chat = shell.pluginSession.require(chatShellService);
      await chat.chat.loadChannels(panels.site);
      for (final panel in ForumPanel.values) {
        expect(chat.openChannel(9), isTrue);
        await tester.pumpAndSettle();
        shell.moveTabToPanel(shell.activeTabId!, panel);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, 'chat-c-9');
        final general = tester.widget<DItem>(
          find.byKey(const ValueKey('chat-inbox-channel-9')),
        );
        expect(general.selectionStyle, DItemSelectionStyle.sidebar);
        expect(general.shape, DItemShape.menu);
        expect(
          tester
              .widget<DItem>(find.byKey(const ValueKey('chat-inbox-channel-9')))
              .selected,
          isTrue,
          reason: 'General follows the conversation in the focused panel',
        );
        await capture(tester, 'chat-sidebar-conversation-${panel.name}');
        final conversation = shell.activeTabId!;
        for (final label in ['Chats', 'Channels', 'Threads']) {
          expect(sidebarDestination(label), findsOneWidget);
        }
        await tester.tap(sidebarDestination('Threads'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DItem>(find.byKey(const ValueKey('chat-inbox-channel-9')))
              .selected,
          isFalse,
          reason: 'a retained conversation is not the focused directory',
        );
        for (final label in ['Chats', 'Channels', 'Threads']) {
          expect(sidebarDestination(label), findsNothing);
        }
        shell.selectTab(conversation);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DItem>(find.byKey(const ValueKey('chat-inbox-channel-9')))
              .selected,
          isTrue,
        );
        for (final label in ['Chats', 'Channels', 'Threads']) {
          expect(sidebarDestination(label), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('Chat directories remain reachable at the tab limit', (
    tester,
  ) async {
    final shell = await panels.pumpTabs(tester, threads: true, voice: false);
    await shell.forumSettings.setShared(
      const SharedAppearance(
        font: ForumFont.openSans,
        interfaceFont: ForumFont.openSans,
      ),
    );
    while (shell.canCreateTab) {
      shell.openContentInNewTab(ContentRoute.newTab());
    }
    await tester.pumpAndSettle();
    final sourceTab = shell.activeTabId;
    await tester.tap(panels.tab('chat'));
    await tester.pumpAndSettle();
    for (final (label, route) in [
      ('Threads', ChatPlugin.myThreadsRouteId),
      ('Channels', ChatPlugin.browseRouteId),
      ('Chats', ChatPlugin.inboxRouteId),
    ]) {
      final navigation = find.byKey(const ValueKey('chat-browse-navigation'));
      await tester.tap(
        label == 'Threads'
            ? sidebarDestination(label)
            : find.descendant(of: navigation, matching: find.text(label)).first,
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, route);
      expect(shell.activeTabId, sourceTab);
      expect(
        shell.currentWorkspace!.tabs,
        hasLength(ForumWorkspace.maximumTabs),
      );
      for (final label in ['Chats', 'Channels', 'Threads']) {
        expect(sidebarDestination(label), findsNothing);
      }
    }
    expect(shell.handleBack(canReturnToSidebar: false), isTrue);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, ChatPlugin.browseRouteId);
    expect(shell.handleForward(), isTrue);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, ChatPlugin.inboxRouteId);
    await capture(tester, 'chat-sidebar-directory-at-tab-limit');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'Chat controls stay pinned through voice rooms at $scale text',
      (tester) async {
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final shell = await panels.pumpTabs(
          tester,
          threads: true,
          roomCount: 40,
        );
        await shell.forumSettings.setShared(
          const SharedAppearance(
            font: ForumFont.openSans,
            interfaceFont: ForumFont.openSans,
          ),
        );
        await tester.tap(panels.tab('chat'));
        await tester.pumpAndSettle();
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        final controls = find.byKey(
          const ValueKey('chat-inbox-activity-filter'),
        );
        final tabsTop = tester.getTopLeft(panels.tabs).dy;
        final scroll = find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.byType(CustomScrollView),
        );
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        await tester.drag(scroll, const Offset(0, -400));
        await tester.pumpAndSettle();
        final pinnedTop = tester.getTopLeft(controls).dy;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        await capture(tester, 'chat-sidebar-voice-end-$scale');
        expect(tester.getTopLeft(controls).dy, closeTo(pinnedTop, .1));
        expect(
          find
              .descendant(of: controls, matching: find.byType(DButton))
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.getTopLeft(panels.tabs).dy, tabsTop);
        final offset = position.pixels;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(controls),
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, lessThan(offset));
        expect(tester.getTopLeft(controls).dy, closeTo(pinnedTop, .1));
        await tester.tap(
          find.descendant(of: controls, matching: find.byType(DButton)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unread').last);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: controls, matching: find.text('Unread')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    testWidgets('Chat controls pin above the scrolling inbox in $mode', (
      tester,
    ) async {
      final shell = await panels.pumpTabs(
        tester,
        threads: true,
        voice: false,
        channels: {
          panels.site: ChatChannels(
            public: [
              for (var id = 1; id <= 50; id++)
                ChatChannel(
                  id: id,
                  title: 'Channel $id',
                  kind: ChatChannelKind.category,
                  membership: const ChatMembership(following: true),
                ),
            ],
          ),
        },
      );
      await shell.forumSettings.setShared(
        const SharedAppearance(
          font: ForumFont.openSans,
          interfaceFont: ForumFont.openSans,
        ),
      );
      await shell.forumSettings.setThemeMode(panels.site, mode);
      await tester.tap(panels.tab('chat'));
      await tester.pumpAndSettle();
      final controls = find.byKey(const ValueKey('chat-inbox-activity-filter'));
      final initialTop = tester.getTopLeft(controls).dy;
      final scroll = find.descendant(
        of: find.byType(InstanceSidebar),
        matching: find.byType(CustomScrollView),
      );
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      position.jumpTo(400);
      await tester.pumpAndSettle();
      final pinnedTop = tester.getTopLeft(controls).dy;
      expect(pinnedTop, lessThan(initialTop));
      position.jumpTo(800);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(controls).dy, closeTo(pinnedTop, .1));
      final button = find.descendant(
        of: controls,
        matching: find.byType(DButton),
      );
      expect(button.hitTestable(), findsOneWidget);
      await capture(tester, 'chat-sidebar-${mode.name}');
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SIDEBAR_FILTER_REVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
