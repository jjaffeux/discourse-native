import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _output = String.fromEnvironment('drawerCaptureOutput');
final _menu = find.byKey(const ValueKey('mobile-menu-button'));
final _tabs = find.byKey(const ValueKey('sidebar-panel-tabs'));
final _panel = find.byKey(const ValueKey('mobile-navigation-panel'));
Finder _side(String value) =>
    find.byKey(ValueKey('sidebar-panel-switch-$value'));

Future<void> _capture(WidgetTester tester, String name) async {
  if (_output.isEmpty) return;
  await tester.runAsync(() async {
    final builder = ui.SceneBuilder();
    tester.binding.renderViews.first.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(390, 844);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_output).create(recursive: true);
    await File('$_output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    scene.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notifications = MethodChannel(
    'org.discourse.native/notification_opens',
  );
  setUpAll(
    () => messenger.setMockMethodCallHandler(notifications, (_) async => null),
  );
  tearDownAll(() => messenger.setMockMethodCallHandler(notifications, null));

  testWidgets(
    'primary drawer links select their mobile place and close navigation',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      for (final (label, place) in [
        ('Messages', MobileTab.messages),
        ('Users', MobileTab.users),
        ('Topics', MobileTab.topics),
      ]) {
        await tester.tap(_menu);
        await tester.pumpAndSettle();
        await tester.tap(sidebarDestination(label));
        await tester.pumpAndSettle();
        expect(shell.mobileNavigation.sidebarOpen, isFalse);
        expect(shell.mobileNavigation.tab, place);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'drawer keeps its mode switch at foot and reselects the foreground',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      await tester.tap(_menu);
      await tester.pumpAndSettle();
      final sidebar = find.descendant(
        of: _panel,
        matching: find.byType(DSidebar),
      );
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byType(ForumIdentityHeader),
        ),
        findsOneWidget,
      );
      for (final label in ['Topics', 'Messages', 'Users']) {
        expect(sidebarDestination(label), findsOneWidget);
      }
      final footerTop = tester.getRect(_tabs).top;
      expect(footerTop, greaterThan(tester.getRect(_panel).center.dy));
      final scrollable = find.descendant(
        of: sidebar,
        matching: find.byType(CustomScrollView),
      );
      await tester.drag(scrollable, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.getRect(_tabs).top, footerTop);

      for (final preview in ['chat', 'shortcuts']) {
        await tester.tap(_side(preview));
        await tester.pumpAndSettle();
        await tester.tap(_menu);
        await tester.pumpAndSettle();
        await tester.tap(_menu);
        await tester.pumpAndSettle();
        expect(tester.widget<DTabs<String>>(_tabs).value, 'forum');
      }
      shell.closeMobileSidebar();
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      await tester.tap(_menu);
      await tester.pumpAndSettle();
      expect(tester.widget<DTabs<String>>(_tabs).value, 'chat');
      await tester.tap(_side('shortcuts'));
      await tester.pumpAndSettle();
      await tester.tap(_menu);
      await tester.pumpAndSettle();
      await tester.tap(_menu);
      await tester.pumpAndSettle();
      expect(tester.widget<DTabs<String>>(_tabs).value, 'chat');
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets(
    'cancelled and system-interrupted drawer swipes restore the panel',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      await tester.tap(_menu);
      await tester.pumpAndSettle();
      final resting = tester.getRect(_panel);
      for (final interruption in ['cancel', 'system', 'short']) {
        final gesture = await tester.startGesture(const Offset(389, 400));
        await gesture.moveBy(Offset(interruption == 'short' ? -40 : -160, 0));
        await tester.pump();
        expect(tester.getRect(_panel).left, lessThan(resting.left));
        if (interruption == 'cancel') {
          await gesture.cancel();
        } else if (interruption == 'system') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await gesture.cancel();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          await tester.pump(const Duration(milliseconds: 300));
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(shell.mobileNavigation.sidebarOpen, isTrue);
        expect(tester.getRect(_panel), resting);
      }
      await tester.dragFrom(const Offset(389, 400), const Offset(-240, 0));
      await tester.pumpAndSettle();
      expect(shell.mobileNavigation.sidebarOpen, isFalse);
      await tester.tap(_menu);
      await tester.pumpAndSettle();
      expect(tester.getRect(_panel), resting);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('render forum and chat drawers with scrolled content', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    if (_output.isNotEmpty) {
      await tester.runAsync(() async {
        final manifest =
            jsonDecode(await rootBundle.loadString('FontManifest.json'))
                as List;
        for (final entry in manifest.cast<Map<String, dynamic>>()) {
          final loader = FontLoader(entry['family'] as String);
          for (final font
              in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
            loader.addFont(rootBundle.load(font['asset'] as String));
          }
          await loader.load();
        }
      });
    }
    final shell = await pumpMobileShellFixture(
      tester,
      chatSearch: true,
      voice: true,
      user: DiscourseUser(
        id: 7,
        username: 'reader',
        canCreateTopic: true,
        canSendPrivateMessages: true,
        sidebarCategoryIds: [for (var id = 1; id <= 15; id++) id],
        plugins: PluginData.none.withValue(
          chatCurrentUserDataKey,
          const ChatCurrentUser(
            hasChatEnabled: true,
            canDirectMessage: true,
            canChat: true,
          ),
        ),
      ),
      conversations: ChatChannels(
        public: [
          for (var id = 1; id <= 20; id++)
            ChatChannel(
              id: id,
              title:
                  [
                    'General',
                    'Support',
                    'Development',
                    'Design',
                    'Site feedback',
                  ][(id - 1) % 5] +
                  (id > 5 ? ' $id' : ''),
              kind: ChatChannelKind.category,
              membership: const ChatMembership(following: true),
              lastMessagePreview: 'The latest updates from the community',
            ),
        ],
      ),
      sidebarCategories: [
        for (final (id, name) in [
          'Support',
          'Development',
          'Design',
          'Community',
          'Announcements',
          'How to guides',
          'Feature requests',
          'Documentation',
          'Translations',
          'Integrations',
          'Events',
          'Themes',
          'Hosting',
          'Plugins',
          'Site feedback',
        ].indexed)
          TopicCategory(
            id: id + 1,
            name: name,
            slug: name.toLowerCase(),
            color: '529EBE',
            topicCount: 20,
          ),
      ],
    );
    await shell.forumSettings.setThemeMode(_site, AppThemeMode.light);
    await shell.forumSettings.setThemes(
      _site,
      ForumThemePreferences.preset('dracula'),
    );
    if (_output.isNotEmpty) {
      await shell.forumSettings.setShared(
        shell.forumSettings.shared.copyWith(
          font: ForumFont.lato,
          interfaceFont: ForumFont.lato,
        ),
      );
    }
    await tester.tap(_menu);
    await tester.pumpAndSettle();
    await _capture(tester, 'forum-drawer');
    Finder list() =>
        find.descendant(of: _panel, matching: find.byType(CustomScrollView));
    await tester.drag(list(), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(sidebarDestination('Topics').hitTestable(), findsNothing);
    await _capture(tester, 'forum-drawer-scrolled');
    await tester.tap(_side('chat'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-inbox-channel-4')).hitTestable(),
      findsOneWidget,
    );
    await _capture(tester, 'chat-drawer');
    final filters = find.byKey(const ValueKey('chat-inbox-activity-filter'));
    final atRest = tester.getRect(filters);
    await tester.drag(list(), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(filters.hitTestable(), findsOneWidget);
    expect(tester.getRect(filters).left, atRest.left);
    expect(tester.getRect(filters).top, atRest.top);
    final search = find.byKey(const ValueKey('chat-search-entry'));
    expect(tester.getRect(search).top - tester.getRect(_panel).top, 6);
    expect(atRest.left - tester.getRect(_panel).left, 6);
    expect(_tabs.hitTestable(), findsOneWidget);
    await _capture(tester, 'chat-drawer-scrolled');
    final scroll = tester.widget<CustomScrollView>(list()).controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Voice rooms'), findsOneWidget);
    expect(
      tester
          .getRect(_panel)
          .contains(tester.getCenter(find.text('Voice rooms'))),
      isTrue,
    );
    expect(tester.getRect(filters), atRest);
    await _capture(tester, 'chat-drawer-voice-section');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
