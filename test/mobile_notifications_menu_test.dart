import 'dart:async';

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
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final rtl in [false, true]) {
      testWidgets(
        'mobile tabs scroll and switch feeds on $platform, RTL $rtl',
        (tester) async {
          await _mount(tester, platform: platform, rtl: rtl);
          final semantics = tester.ensureSemantics();
          try {
            await tester.tap(find.byKey(UserMenuButton.bellKey));
            await tester.pumpAndSettle();

            expect(find.byType(DSheetContent), findsNothing);
            expect(find.byType(NotificationSection), findsOneWidget);
            final panel = find.byType(UserMenuPanel);
            final tabs = find.byKey(const ValueKey('user-menu-mobile-tabs'));
            final panelRect = tester.getRect(panel);
            final tabsRect = tester.getRect(tabs);
            expect(
              panelRect.top,
              greaterThan(
                tester.getRect(find.byKey(UserMenuButton.bellKey)).bottom,
              ),
            );
            expect(panelRect.width, UserMenuPanel.mobileWidth);
            expect(
              tabsRect.top,
              lessThan(tester.getRect(find.byType(NotificationSection)).top),
            );
            expect(
              tester.getSemantics(_tab('all')),
              isSemantics(label: 'Notifications, 3 unread', isSelected: true),
            );

            // Scrolling the feed must leave navigation fixed at the top.
            await tester.drag(
              find.descendant(of: panel, matching: find.byType(ListView)),
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
              isSemantics(isSelected: true),
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

            await tester.tapAt(const Offset(190, 720));
            await tester.pumpAndSettle();
            expect(find.byType(UserMenuPanel), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  for (final dark in [false, true]) {
    testWidgets('320px popup supports 200% text and keyboard, dark $dark', (
      tester,
    ) async {
      await _mount(tester, width: 320, scale: 2, dark: dark);
      await tester.tap(find.byKey(UserMenuButton.bellKey));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(UserMenuPanel));
      expect(rect.left, greaterThanOrEqualTo(UserMenuPanel.margin));
      expect(rect.right, lessThanOrEqualTo(320 - UserMenuPanel.margin));
      expect(rect.bottom, lessThanOrEqualTo(800 - UserMenuPanel.margin));
      // Each tab answers exactly where its pill is painted, and the pill
      // grows to hold its label at 200% text.
      for (final tab in find.byType(DTabTrigger<String>).evaluate()) {
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
          find.descendant(of: trigger, matching: find.byType(Text)),
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
          ('all', 'Notifications'),
          ('likes', 'Likes'),
          ('other', 'Other'),
        ]) {
          expect(tester.getSemantics(_tab(id)).label, label, reason: id);
        }
        if (width >= 600) {
          for (final (id, count) in [
            ('replies', '3'),
            ('messages', '2'),
            ('bookmarks', '1'),
          ]) {
            expect(
              find.descendant(
                of: _tab(id),
                matching: find.descendant(
                  of: find.byType(DBadge),
                  matching: find.text(count),
                ),
              ),
              findsOneWidget,
              reason: id,
            );
          }
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
          expect(tester.getSemantics(_tab(id)).label, label, reason: id);
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

  testWidgets('touch section list counts grouped unread notifications', (
    tester,
  ) async {
    final controller = await _mount(tester);
    await tester.tap(find.byKey(UserMenuButton.bellKey));
    await tester.pumpAndSettle();
    unawaited(showUserMenuSheet(tester.element(find.byType(UserMenuPanel))));
    await tester.pumpAndSettle();
    controller.accountActivity.applyLiveNotificationState(
      'https://meta.example',
      const {
        'all_unread_notifications_count': 0,
        'new_personal_messages_notifications_count': 0,
        'grouped_unread_notifications': {'2': 3, '6': 2, '24': 1},
      },
    );
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('user-menu-sheet'));
    for (final (label, count) in [
      ('Replies', '3'),
      ('Messages', '2'),
      ('Bookmarks', '1'),
    ]) {
      final tile = find.ancestor(
        of: find.descendant(of: sheet, matching: find.text(label)),
        matching: find.byType(DItem),
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.descendant(
            of: find.byType(DBadge),
            matching: find.text(count),
          ),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    expect(tester.takeException(), isNull);
  });
}

Finder _tab(String id) => find.byKey(ValueKey('user-menu-tab-$id'));

Future<ShellController> _mount(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.iOS,
  double width = 390,
  double scale = 1,
  bool rtl = false,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 800);
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
        for (var id = 1; id <= 20; id++)
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
