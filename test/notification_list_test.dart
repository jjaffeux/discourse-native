import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://forum.example';
const _rowKey = ValueKey('notification-row-1');

void main() {
  for (final (section, type) in const [
    ('all', CoreNotificationTypes.replied),
    ('replies', CoreNotificationTypes.replied),
    ('likes', CoreNotificationTypes.liked),
    ('other', CoreNotificationTypes.edited),
    ('bookmarks', CoreNotificationTypes.bookmarkReminder),
  ]) {
    testWidgets(
      'middle-click in $section opens the notification post in a background tab and keeps the menu open',
      (tester) async {
        final (controller, api) = await _pumpMenu(tester, type: type);
        if (section != 'all') {
          await tester.tap(find.byKey(ValueKey('user-menu-tab-$section')));
          await tester.pumpAndSettle();
        }
        final original = controller.activeTab;

        await tester.tap(
          find.byKey(_rowKey),
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await tester.pumpAndSettle();

        expect(controller.activeTab, original);
        expect(controller.tabsForCurrentForum, hasLength(2));
        final opened = controller.tabsForCurrentForum.last.currentContent;
        expect(opened.topicId, 42);
        expect(opened.postNumber, 7);
        expect(api.markedRead, [1]);
        expect(find.byType(UserMenuPanel), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets('primary click opens the notification and dismisses the menu', (
    tester,
  ) async {
    final (controller, api) = await _pumpMenu(tester);
    final originalId = controller.activeTabId;

    await tester.tap(find.byKey(_rowKey));
    await tester.pumpAndSettle();

    expect(controller.activeTabId, originalId);
    expect(controller.tabsForCurrentForum, hasLength(1));
    expect(controller.currentContent?.topicId, 42);
    expect(controller.currentContent?.postNumber, 7);
    expect(api.markedRead, [1]);
    expect(find.byType(UserMenuPanel), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'middle-button drags and cancelled clicks leave notifications unread',
    (tester) async {
      final (controller, api) = await _pumpMenu(tester);
      final original = controller.activeTab;
      final position = tester.getCenter(find.byKey(_rowKey));
      final drag = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await drag.moveBy(const Offset(100, 0));
      await drag.up();
      await tester.pumpAndSettle();

      final cancelled = await tester.startGesture(
        position,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await cancelled.cancel();
      await tester.pumpAndSettle();

      expect(controller.activeTab, original);
      expect(controller.tabsForCurrentForum, hasLength(1));
      expect(api.markedRead, isEmpty);
      expect(find.byType(UserMenuPanel), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

Future<(ShellController, FakeDiscourseApi)> _pumpMenu(
  WidgetTester tester, {
  NotificationWireType type = CoreNotificationTypes.replied,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const user = DiscourseUser(id: 1, username: 'reader');
  final notification = DiscourseNotification.test(
    id: 1,
    typeId: NotificationTypeId(type.wireId),
    topicId: 42,
    postNumber: 7,
    slug: 'notification-topic',
    title: 'Notification topic',
    data: const {'display_username': 'sam'},
  );
  final api = FakeDiscourseApi(
    user: user,
    notificationList: [notification],
    replyNotificationList: [notification],
    likeNotificationList: [notification],
    otherNotificationList: [notification],
    reminderList: [notification],
    bookmarkList: const [],
    feeds: const {'/latest.json': []},
  );
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore([
        instance('forum.example').copyWith(user: user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(UserMenuButton.avatarKey));
  await tester.pumpAndSettle();
  return (ShellScope.read(tester.element(find.byType(UserMenuPanel))), api);
}
