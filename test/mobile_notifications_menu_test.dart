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
      for (final tab in find.byType(DTabTrigger<String>).evaluate()) {
        expect(
          tester.getSize(find.byWidget(tab.widget)).height,
          greaterThanOrEqualTo(48),
        );
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
}

Finder _tab(String id) => find.byKey(ValueKey('user-menu-tab-$id'));

Future<void> _mount(
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
}
