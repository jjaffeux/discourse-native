import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  notificationScrollTests();

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final rtl in [false, true]) {
      testWidgets(
        'mobile sheet tabs scroll and switch feeds on $platform, RTL $rtl',
        (tester) async {
          await _mount(tester, platform: platform, rtl: rtl);
          final semantics = tester.ensureSemantics();
          try {
            await tester.tap(find.byKey(UserMenuButton.bellKey));
            await tester.pumpAndSettle();

            final sheet = find.byType(DSheetContent);
            expect(sheet, findsOneWidget);
            expect(tester.widget<DSheetContent>(sheet).side, DSheetSide.bottom);
            expect(
              tester.widget<DSheetContent>(sheet).variant,
              DSheetVariant.adaptiveMenu,
            );
            expect(find.byType(DSheetHeader), findsNothing);
            expect(find.byType(NotificationSection), findsOneWidget);
            final panel = find.byType(UserMenuPanel);
            final tabs = find.byKey(const ValueKey('user-menu-mobile-tabs'));
            final sheetRect = tester.getRect(sheet);
            expect(sheetRect.width, 390);
            expect(sheetRect.top, closeTo(800 * .45, 1));
            expect(sheetRect.bottom, greaterThanOrEqualTo(800));
            expect(
              tester.getRect(tabs).top,
              lessThan(
                tester
                    .getRect(find.byKey(const ValueKey('notification-row-1')))
                    .top,
              ),
            );
            expect(
              tester.getSemantics(_tab('all')),
              isSemantics(label: 'All, 3 unread', isToggled: true),
            );

            // The first upward pull expands the Native sheet. Subsequent
            // scrolling leaves the notification navigation fixed at the top.
            await tester.drag(
              find.byKey(const ValueKey('sheet-drag-handle')),
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(sheet).top, lessThan(sheetRect.top));
            final tabsRect = tester.getRect(tabs);
            await tester.drag(
              find.descendant(
                of: panel,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable && widget.axis == Axis.vertical,
                ),
              ),
              const Offset(0, -180),
            );
            await tester.pumpAndSettle();
            expect(tester.getRect(tabs), tabsRect);

            await tester.tap(_tab('replies'));
            await tester.pumpAndSettle();
            expect(find.byType(RepliesSection), findsOneWidget);
            expect(find.textContaining('Reply feed item'), findsOneWidget);
            expect(
              tester.getSemantics(_tab('replies')),
              isSemantics(isToggled: true),
            );

            final scrollable = find.descendant(
              of: tabs,
              matching: find.byType(Scrollable),
            );
            await tester.drag(tabs, Offset(rtl ? 650 : -650, 0));
            await tester.pumpAndSettle();
            expect(
              tester.state<ScrollableState>(scrollable).position.pixels,
              greaterThan(0),
            );
            expect(_tab('other').hitTestable(), findsOneWidget);
            await tester.tap(_tab('other'));
            await tester.pumpAndSettle();
            expect(find.byType(OtherNotificationsSection), findsOneWidget);
            expect(find.byType(UserMenuPanel), findsOneWidget);

            await tester.drag(
              find.byKey(const ValueKey('sheet-drag-handle')),
              const Offset(0, 650),
            );
            await tester.pumpAndSettle();
            expect(find.byType(UserMenuPanel), findsNothing);
            expect(find.byType(DSheetContent), findsNothing);
            expect(
              tester
                  .widget<DButton>(find.byKey(UserMenuButton.bellKey))
                  .expanded,
              isFalse,
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'expanded notification feed fills the Native sheet on $platform',
      (tester) async {
        tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
        await _mount(tester, platform: platform, height: 1000);
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('sheet-drag-handle')),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        final sheet = tester.getRect(find.byType(DSheetContent));
        final panel = tester.getRect(find.byType(UserMenuPanel));
        expect(sheet.top, closeTo(47 + 8, 1));
        const dock = DMobileDockGeometry(foot: 34);
        final inner = sheet.bottom - (34 - dock.endLift);
        expect(sheet.bottom, closeTo(1000 - dock.endLift, 1));
        expect(panel.bottom, closeTo(inner, 1));
        expect(panel.height, greaterThan(640));
        final feed = find.descendant(
          of: find.byType(UserMenuPanel),
          matching: find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.vertical,
          ),
        );
        expect(tester.getRect(feed).bottom, closeTo(inner, 1));
        final tabs = find.byKey(const ValueKey('user-menu-mobile-tabs'));
        final tabsRect = tester.getRect(tabs);
        await tester.drag(feed, const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(tester.getRect(tabs), tabsRect);

        await tester.tap(_tab('replies'));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(UserMenuPanel)), panel);
        expect(tester.getRect(feed).bottom, closeTo(inner, 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'unexpanded sheet keeps its opening height across tabs on $platform',
      (tester) async {
        await _mount(tester, platform: platform);
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        final sheet = find.byType(DSheetContent);
        final opened = tester.getRect(sheet);
        expect(opened.height, closeTo(800 * .55, 1));
        for (final id in [
          'replies',
          'likes',
          'messages',
          'bookmarks',
          'other',
          'all',
        ]) {
          await tester.ensureVisible(_tab(id));
          await tester.pumpAndSettle();
          await tester.tap(_tab(id));
          await tester.pumpAndSettle();
          // Native floating clearance stays inside the opening viewport.
          // Short content must not move its upper edge toward the screen foot.
          final bounds = tester.getRect(sheet);
          expect(bounds.top, closeTo(opened.top, .01), reason: id);
          expect(
            bounds.height,
            greaterThanOrEqualTo(opened.height - 6),
            reason: id,
          );
        }
        expect(tester.getRect(sheet).left, 0);
        expect(tester.getRect(sheet).right, 390);
        await tester.drag(
          find.byKey(const ValueKey('sheet-drag-handle')),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(sheet).height, greaterThan(opened.height));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final unread in [0, 3]) {
    testWidgets(
      'sheet dismisses through backdrop and reopens with $unread unread',
      (tester) async {
        final controller = await _mount(tester);
        controller.accountActivity.applyLiveNotificationState(
          'https://meta.example',
          {'all_unread_notifications_count': unread},
        );
        await tester.pumpAndSettle();
        final bell = find.byKey(UserMenuButton.bellKey);
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsOneWidget);
        expect(tester.widget<DButton>(bell).expanded, isTrue);

        await tester.tapAt(const Offset(100, 100));
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsNothing);
        expect(tester.widget<DButton>(bell).expanded, isFalse);

        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.byType(DSheetContent), findsOneWidget);
        expect(find.byType(NotificationSection), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets('320px sheet supports 200% text and keyboard, dark $dark', (
      tester,
    ) async {
      await _mount(tester, width: 320, scale: 2, dark: dark);
      await tester.tap(find.byKey(UserMenuButton.bellKey));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(UserMenuPanel));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, inInclusiveRange(0, 800));
      // Each tab answers exactly where its pill is painted, and the pill
      // grows to hold its label at 200% text.
      for (final tab in find.byType(DToggle).evaluate()) {
        final trigger = find.byWidget(tab.widget);
        final bounds = tester.getRect(trigger);
        expect(
          bounds,
          tester.getRect(
            find.descendant(
              of: trigger,
              matching: find.byType(AnimatedContainer),
            ),
          ),
        );
        final label = tester.getRect(
          find.descendant(of: trigger, matching: find.byType(Text)).first,
        );
        expect(bounds.expandToInclude(label), bounds);
      }
      final focus = tester
          .widget<FocusableActionDetector>(
            find.descendant(
              of: _tab('all'),
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!;
      focus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(_tab('other').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(OtherNotificationsSection), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 900.0]) {
    testWidgets('reply, message and bookmark tabs count grouped unread '
        'notifications at ${width}px', (tester) async {
      final controller = await _mount(tester, width: width);
      final semantics = tester.ensureSemantics();
      try {
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        // Opening the Notifications tab bumps the seen marker, so core
        // publishes seen-scoped totals of zero while the grouped counts still
        // hold what is unread: mentioned 1, replied 1, group_mentioned 1,
        // private_message 2, bookmark_reminder 1.
        controller.accountActivity.applyLiveNotificationState(
          'https://meta.example',
          const {
            'all_unread_notifications_count': 0,
            'new_personal_messages_notifications_count': 0,
            'grouped_unread_notifications': {
              '1': 1,
              '2': 1,
              '15': 1,
              '6': 2,
              '24': 1,
            },
          },
        );
        await tester.pumpAndSettle();

        for (final (id, label) in [
          ('replies', 'Replies, 3 unread'),
          ('messages', 'Messages, 2 unread'),
          ('bookmarks', 'Bookmarks, 1 unread'),
          ('all', 'All, 6 unread'),
          ('likes', 'Likes'),
          ('other', 'Other'),
        ]) {
          await tester.ensureVisible(_tab(id));
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(_tab(id)),
            isSemantics(label: label),
            reason: id,
          );
        }
        for (final (id, count) in [
          ('replies', '3'),
          ('messages', '2'),
          ('bookmarks', '1'),
        ]) {
          expect(
            find.descendant(of: _tab(id), matching: find.text(count)),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('tabs without grouped unread notifications carry no badge '
        'at ${width}px', (tester) async {
      final controller = await _mount(tester, width: width);
      final semantics = tester.ensureSemantics();
      try {
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        // The seen-scoped message count is not the Messages tab's: only an
        // unread private_message notification is.
        controller.accountActivity.applyLiveNotificationState(
          'https://meta.example',
          const {
            'all_unread_notifications_count': 0,
            'new_personal_messages_notifications_count': 2,
            'grouped_unread_notifications': {'2': 0, '6': 0, '24': 0},
          },
        );
        await tester.pumpAndSettle();

        for (final (id, label) in [
          ('replies', 'Replies'),
          ('messages', 'Messages'),
          ('bookmarks', 'Bookmarks'),
        ]) {
          await tester.ensureVisible(_tab(id));
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(_tab(id)),
            isSemantics(label: label),
            reason: id,
          );
          expect(
            find.descendant(of: _tab(id), matching: find.byType(DBadge)),
            findsNothing,
            reason: id,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}

void notificationScrollTests() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'long notification feed mounts only nearby rows at $scale text',
      (tester) async {
        final controller = await _mount(
          tester,
          notificationCount: 200,
          scale: scale,
        );
        await tester.tap(find.byKey(UserMenuButton.bellKey));
        await tester.pumpAndSettle();
        final openedRows = find.byType(NotificationRow).evaluate().length;
        debugPrint(
          'notification-scroll opened rows=$openedRows total=200 scale=$scale',
        );
        expect(openedRows, lessThan(40));
        expect(
          find.byKey(const ValueKey('notification-row-200')),
          findsNothing,
        );

        await tester.drag(
          find.byKey(const ValueKey('sheet-drag-handle')),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        final tabs = find.byKey(const ValueKey('user-menu-mobile-tabs'));
        final tabsRect = tester.getRect(tabs);
        final scrollable = find.descendant(
          of: find.byType(UserMenuPanel),
          matching: find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.vertical,
          ),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('notification-row-200')),
          500,
          scrollable: scrollable,
          maxScrolls: 100,
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(tabs), tabsRect);
        expect(find.byType(NotificationRow).evaluate().length, lessThan(40));
        expect(find.byKey(const ValueKey('notification-row-1')), findsNothing);
        expect(
          find.byKey(const ValueKey('notification-row-200')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('notification-row-200')));
        await tester.pumpAndSettle();
        expect(
          controller
              .notificationsFor('https://meta.example')
              .notifications
              .last
              .read,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _tab(String id) => find.descendant(
  of: find.ancestor(
    of: find.byKey(ValueKey('user-menu-tab-$id')),
    matching: find.byType(DToggle),
  ),
  matching: find.byType(MergeSemantics),
);

Future<ShellController> _mount(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.iOS,
  double width = 390,
  double height = 800,
  double scale = 1,
  bool rtl = false,
  bool dark = false,
  int notificationCount = 20,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(id: 7, username: 'reader');
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.example').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      totals: const NotificationTotals(unreadNotifications: 3),
      notificationList: [
        for (var id = 1; id <= notificationCount; id++)
          DiscourseNotification.test(
            id: id,
            typeId: const NotificationTypeId(2),
            title: 'Notification item $id',
            data: const {'display_username': 'alice'},
          ),
      ],
      replyNotificationList: const [
        DiscourseNotification.test(
          id: 21,
          typeId: NotificationTypeId(2),
          title: 'Reply feed item',
          data: {'display_username': 'bob'},
        ),
      ],
    ),
    authenticator: FakeAuthenticator()..keys['https://meta.example'] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  await controller.accountActivity.refresh(controller.currentInstance!);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: platform,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: const Scaffold(
          body: Align(
            alignment: AlignmentDirectional.topEnd,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: UserMenuButton(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}
