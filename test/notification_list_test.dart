import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/topic_post_list.dart';

const _siteUrl = 'https://forum.example';
const _rowKey = ValueKey('notification-row-1');

void main() {
  for (final postNumber in [1, 7]) {
    for (final startingPoint in ['new topic', 'same topic', 'another topic']) {
      testWidgets(
        'clicking post $postNumber notification from $startingPoint reveals the post',
        (tester) async {
          final posts = [
            for (var number = 1; number <= 30; number++)
              Post(
                id: number,
                postNumber: number,
                username: 'sam',
                cooked: '<p>Notification target $number</p>' * 4,
              ),
          ];
          final (controller, api) = await _pumpMenu(
            tester,
            postNumber: postNumber,
            topics: {
              42: (
                detail: TopicDetail(
                  id: 42,
                  title: 'Notification topic',
                  stream: [for (final post in posts) post.id],
                  postsCount: posts.length,
                  lastReadPostNumber: 23,
                ),
                posts: posts,
              ),
              43: topicPayload(id: 43, title: 'Another topic'),
            },
          );
          if (startingPoint != 'new topic') {
            await tester.tap(find.byKey(UserMenuButton.bellKey));
            await tester.pumpAndSettle();
            controller.openTopicUrl('$_siteUrl/t/notification-topic/42/20');
            await tester.pumpAndSettle();
            expect(controller.topicScrollPostNumber(42), 20);
            controller.saveTopicScrollPost(42, 20, viewportOffset: -24);
            if (startingPoint == 'another topic') {
              controller.openTopicUrl('$_siteUrl/t/another-topic/43/1');
              await tester.pumpAndSettle();
            }
            await tester.tap(find.byKey(UserMenuButton.bellKey));
            await tester.pumpAndSettle();
          }

          await tester.tap(find.byKey(_rowKey));
          await tester.pumpAndSettle();

          final target = find.byKey(ValueKey(postNumber));
          expect(target, findsOneWidget);
          final viewport = tester.getRect(topicPostListFinder());
          expect(tester.getRect(target).overlaps(viewport), isTrue);
          expect(
            tester.getTopLeft(target).dy,
            greaterThanOrEqualTo(viewport.top),
          );
          expect(controller.topicScrollPostNumber(42), postNumber);
          expect(api.markedRead, [1]);
          expect(find.byType(UserMenuPanel), findsNothing);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'read and unread rows switch hover immediately in ${brightness.name} mode',
      (tester) async {
        final theme = brightness == Brightness.dark
            ? AppTheme.dark
            : AppTheme.light;
        var opens = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              backgroundColor: theme.shell.floating,
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final read in [false, true])
                        NotificationRow(
                          siteUrl: _siteUrl,
                          notification: DiscourseNotification.test(
                            id: read ? 2 : 1,
                            typeId: const NotificationTypeId(2),
                            read: read,
                            title: 'A useful topic',
                            data: const {'display_username': 'sam'},
                          ),
                          onTap: () => opens++,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rows = find.byType(NotificationRow);
        final tokens = DTokens.of(tester.element(rows.first));
        final backdrop = theme.shell.floating;
        final unread = Color.alphaBlend(
          tokens.primary.withValues(alpha: .12),
          backdrop,
        );
        Color background(int index) => _rowBackground(rows.at(index), backdrop);
        expect(background(0), unread);
        expect(background(1), backdrop);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(600, 400));
        addTearDown(mouse.removePointer);
        for (final hovered in [0, 1, 0]) {
          await mouse.moveTo(tester.getCenter(rows.at(hovered)));
          for (final frame in [
            Duration.zero,
            const Duration(milliseconds: 16),
          ]) {
            await tester.pump(frame);
            expect(background(hovered), tokens.muted);
            expect(background(1 - hovered), hovered == 0 ? backdrop : unread);
          }
        }
        await mouse.moveTo(const Offset(600, 400));
        await tester.pump();
        expect(background(0), unread);
        expect(background(1), backdrop);
        expect(opens, 0);
        expect(
          tester
              .widget<DIcon>(
                find.descendant(of: rows.first, matching: find.byType(DIcon)),
              )
              .color,
          tokens.primary,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

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

Color _rowBackground(Finder row, Color backdrop) {
  var color = backdrop;
  for (final box
      in find
          .descendant(of: row, matching: find.byType(DecoratedBox))
          .evaluate()) {
    final decoration = (box.renderObject! as RenderDecoratedBox).decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      color = Color.alphaBlend(decoration.color!, color);
    }
  }
  return color;
}

Future<(ShellController, FakeDiscourseApi)> _pumpMenu(
  WidgetTester tester, {
  NotificationWireType type = CoreNotificationTypes.replied,
  int postNumber = 7,
  Map<int, TopicPayload> topics = const {},
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const user = DiscourseUser(id: 1, username: 'reader');
  final notification = DiscourseNotification.test(
    id: 1,
    typeId: NotificationTypeId(type.wireId),
    topicId: 42,
    postNumber: postNumber,
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
    topics: topics,
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
  await tester.tap(find.byKey(UserMenuButton.bellKey));
  await tester.pumpAndSettle();
  return (ShellScope.read(tester.element(find.byType(UserMenuPanel))), api);
}
