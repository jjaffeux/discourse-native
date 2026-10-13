import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_menu.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/desktop_header_menu.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _captureKey = ValueKey('desktop-header-capture');

void main() {
  testWidgets('all desktop header actions show the hand cursor on hover', (
    tester,
  ) async {
    await _pump(tester, width: 1000, dark: true, scale: 1);
    final mouse = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
      pointer: 1,
    );
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final key in [
      TopicCreateButton.buttonKey,
      TopicCreateButton.draftsButtonKey,
      ChatHeaderButton.buttonKey,
      UserMenuButton.bellKey,
      UserMenuButton.avatarKey,
    ]) {
      final rect = tester.getRect(find.byKey(key));
      for (final point in [
        rect.center,
        Offset(rect.left + 2, rect.center.dy),
        Offset(rect.right - 2, rect.center.dy),
      ]) {
        await mouse.moveTo(point);
        await tester.pumpAndSettle();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
          reason: '$key at $point',
        );
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          null,
        ),
  );
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });

  for (final (width, dark, scale) in [
    (1440.0, false, 1.0),
    (1000.0, true, 1.0),
    (1440.0, true, 2.0),
  ]) {
    testWidgets(
      'desktop menus share composition and dismiss at $width dark=$dark scale=$scale',
      (tester) async {
        final (shell, api) = await _pump(
          tester,
          width: width,
          dark: dark,
          scale: scale,
        );
        final header = tester.getRect(find.byType(ShellTitleBar));
        final search = tester.getRect(find.byType(DInputGroup));
        final profile = tester.getRect(find.byKey(UserMenuButton.avatarKey));
        final bell = tester.getRect(find.byKey(UserMenuButton.bellKey));
        final chat = tester.getRect(find.byKey(ChatHeaderButton.buttonKey));
        final create = tester.getRect(find.byKey(TopicCreateButton.buttonKey));
        final drafts = tester.getRect(
          find.byKey(TopicCreateButton.draftsButtonKey),
        );
        expect(profile.size, Size.square(36 * scale));
        expect(profile.right, header.right - 14);
        expect(profile.left - bell.right, 11);
        expect(bell.left - chat.right, 6);
        expect(chat.left - drafts.right, 15);
        expect(create.left - search.right, 14);
        expect(create.height + 8, search.height);
        expect(drafts.height + 8, search.height);
        expect(profile.top, greaterThanOrEqualTo(header.top + 8));
        expect(profile.bottom, lessThanOrEqualTo(header.bottom - 4));
        if (scale == 1) {
          expect(header.height, 49);
          expect(search.height, 36);
          expect(create.width, 36);
          expect(drafts.width, 32);
          expect(chat.height, 28);
          expect(bell.height, 28);
          expect(search.top - header.top, 8.5);
        }
        await _capture(tester, 'shell-$width-$dark-$scale');
        await tester.tap(find.byKey(ChatHeaderButton.buttonKey));
        await tester.pumpAndSettle();
        expect(find.byType(ChatHeaderMenu), findsOneWidget);
        expect(find.text('Open chat'), findsOneWidget);
        final rows = find.byType(DesktopHeaderMenuRow);
        expect(rows, findsNWidgets(2));
        expect(tester.widget<DesktopHeaderMenuRow>(rows.first).unread, isTrue);
        expect(tester.widget<DesktopHeaderMenuRow>(rows.first).count, 3);
        expect(
          find.descendant(
            of: find.byType(DToggleGroup<ChatInboxKind>),
            matching: find.text('3'),
          ),
          findsNWidgets(2),
        );
        expect(find.text('sam: New message'), findsOneWidget);
        final menuWidth = tester
            .getSize(find.byType(DDropdownMenuContent))
            .width;
        await _capture(tester, 'chat-$width-$dark-$scale');
        await tester.tap(rows.first);
        await tester.pumpAndSettle();
        expect(find.byType(ChatHeaderMenu), findsNothing);
        expect(shell.currentContent?.id, 'chat-c-9');
        await tester.tap(find.byKey(ChatHeaderButton.buttonKey));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ChatHeaderMenu), findsNothing);
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        expect(find.text('Mark all read'), findsOneWidget);
        expect(find.byType(DToggleGroup<String>), findsOneWidget);
        expect(
          tester.getSize(find.byType(DDropdownMenuContent)).width,
          menuWidth,
        );
        expect(find.byType(DesktopHeaderMenuRow), findsNWidgets(2));
        await _capture(tester, 'notifications-$width-$dark-$scale');
        await tester.tap(find.text('Mark all read'));
        await tester.pumpAndSettle();
        expect(
          api.markedTypesRead.single,
          contains(const NotificationTypeName('replied')),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(UserMenuPanel), findsNothing);
        await tester.tap(find.byKey(ChatHeaderButton.buttonKey));
        await tester.pumpAndSettle();
        expect(find.byType(ChatHeaderMenu), findsOneWidget);
        shell.lifecycle.invalidate(_site);
        shell.clearAccountSessionState(_site);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ChatHeaderMenu), findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}

Future<(ShellController, FakeDiscourseApi)> _pump(
  WidgetTester tester, {
  required double width,
  required bool dark,
  required double scale,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.platformBrightnessTestValue = dark
      ? Brightness.dark
      : Brightness.light;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final user = DiscourseUser(
    id: 7,
    username: 'reader',
    canCreateTopic: true,
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(chatEnabled: true),
    ),
  );
  final api = FakeDiscourseApi(
    user: user,
    siteConfigs: {_site: config},
    feeds: const {'/latest.json': []},
    totals: chatNotificationTotals(unreadNotifications: 1),
    notificationList: const [
      DiscourseNotification.test(
        id: 1,
        typeId: NotificationTypeId(2),
        topicId: 42,
        title: 'A live topic',
        data: {'display_username': 'sam'},
      ),
      DiscourseNotification.test(
        id: 2,
        typeId: NotificationTypeId(5),
        read: true,
        title: 'Already read',
      ),
    ],
    chatMessagesByKey: {
      FakeDiscourseApi.chatMessagesKey(9): (
        messages: const <ChatMessage>[],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: null,
      ),
    },
    chatChannelsBySite: {
      _site: const ChatChannels(
        public: [
          ChatChannel(
            id: 8,
            title: 'Read channel',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
          ),
          ChatChannel(
            id: 9,
            title: 'Unread channel',
            kind: ChatChannelKind.category,
            membership: ChatMembership(following: true),
            tracking: ChatTracking(unreadCount: 2, mentionCount: 3),
            lastMessageId: 4,
            lastMessagePreview: 'New message',
            lastMessageUsername: 'sam',
          ),
        ],
        direct: [],
        presence: ChatPresence(),
      ),
    },
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: DiscourseApp(
        store: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: user, config: config),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        initialRootMode: ShellRootMode.forum,
        pluginManifest: bundledWidgetTestManifest,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final shell = ShellScope.read(tester.element(find.byType(MainContent).first));
  await shell.forumSettings.setShared(
    shell.forumSettings.shared.copyWith(interfaceFont: ForumFont.lato),
  );
  await tester.pumpAndSettle();
  return (shell, api);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['DESKTOP_PARITY_CAPTURES'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
