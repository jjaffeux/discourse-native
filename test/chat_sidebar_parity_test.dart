import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_panel_tabs_test.dart' as panels;

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

  testWidgets('the side is the one list: its own rows lead to the threads '
      'and to every channel, with no directory rows over it', (tester) async {
    final shell = await panels.pumpTabs(tester, threads: true, voice: false);
    final forumTab = shell.activeTabId!;
    await tester.tap(panels.tab('chat'));
    await tester.pumpAndSettle();
    for (final label in ['Chats', 'Channels', 'Threads']) {
      expect(_directory(label), findsNothing);
    }
    final threads = find.descendant(
      of: find.byType(InstanceSidebar),
      matching: find.byKey(const ValueKey('chat-inbox-threads-card')),
    );
    final channels = find.descendant(
      of: find.byType(InstanceSidebar),
      matching: find.byKey(const ValueKey('chat-inbox-channels-card')),
    );
    expect(threads, findsOneWidget);
    expect(channels, findsOneWidget);
    expect(
      tester.getRect(threads).top,
      greaterThan(
        tester
            .getRect(find.byKey(const ValueKey('chat-inbox-sort-filter')))
            .bottom,
      ),
    );

    await tester.tap(channels);
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('chat-channel-panel-field'));
    expect(panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);

    await tester.tap(threads);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, ChatRoute.myThreadsRouteId);
    expect(tester.widget<DTabs<String>>(panels.tabs).value, 'chat');
    expect(threads, findsOneWidget, reason: 'The list stays beside its page');
    expect(tester.takeException(), isNull);

    shell.selectTab(forumTab);
    await tester.pumpAndSettle();
    expect(shell.activeTabId, forumTab);
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
        // The open chat keeps the page's tint and leading accent edge.
        expect(general.selectionStyle, DItemSelectionStyle.leadingAccent);
        expect(general.shape, DItemShape.fullWidth);
        expect(
          tester
              .widget<DItem>(find.byKey(const ValueKey('chat-inbox-channel-9')))
              .selected,
          isTrue,
          reason: 'General follows the conversation in the focused panel',
        );
        await capture(tester, 'chat-sidebar-conversation-${panel.name}');
        final conversation = shell.activeTabId!;
        shell.openContentInNewTab(
          const ContentRoute(
            destination: ExtensionDestination(ChatRoute.myThreadsRouteId),
            title: 'Threads',
            icon: DIcons.comments,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DItem>(find.byKey(const ValueKey('chat-inbox-channel-9')))
              .selected,
          isFalse,
          reason: 'a retained conversation is not the focused directory',
        );
        shell.selectTab(conversation);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DItem>(find.byKey(const ValueKey('chat-inbox-channel-9')))
              .selected,
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

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
        final controls = find.byKey(const ValueKey('chat-inbox-sort-filter'));
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
        await tester.scrollUntilVisible(
          find.text('View 36 more'),
          200,
          scrollable: find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('View 36 more'));
        await tester.pumpAndSettle();
        final pinnedTop = tester.getTopLeft(controls).dy;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        await capture(tester, 'chat-sidebar-voice-end-$scale');
        expect(tester.getTopLeft(controls).dy, closeTo(pinnedTop, .1));
        expect(
          find
              .descendant(of: controls, matching: find.byType(DToggle))
              .hitTestable(),
          findsNWidgets(2),
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
          find.descendant(of: controls, matching: find.byTooltip('Newest')),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: controls, matching: find.byTooltip('Newest')),
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
      final controls = find.byKey(const ValueKey('chat-inbox-sort-filter'));
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
      expect(pinnedTop, closeTo(initialTop, .1));
      position.jumpTo(800);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(controls).dy, closeTo(pinnedTop, .1));
      final button = find.descendant(
        of: controls,
        matching: find.byType(DToggle),
      );
      expect(button.hitTestable(), findsNWidgets(2));
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

/// A directory's own destination, apart from the ways chat's list holds to
/// the same pages.
Finder _directory(String label) => find.descendant(
  of: find.byType(SidebarDestinationTile),
  matching: find.text(label),
);
