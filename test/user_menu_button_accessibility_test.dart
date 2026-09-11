import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  testWidgets('bell owns unread activity and avatar opens profile directly', (
    tester,
  ) async {
    const user = DiscourseUser(id: 7, username: 'reader', name: 'Reader');
    final site = instance('meta.example').copyWith(user: user);
    final api = FakeDiscourseApi(
      user: user,
      totals: const NotificationTotals(unreadNotifications: 2),
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    );
    await controller.load();
    await controller.accountActivity.refresh(controller.currentInstance!);
    addTearDown(controller.dispose);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(body: Center(child: UserMenuButton())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(UserMenuButton.bellKey);
      expect(tester.getSize(button), const Size.square(36));
      expect(find.byKey(UserMenuButton.unreadDotKey), findsOneWidget);
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.byTooltip('Profile'), findsOneWidget);
      final node = tester.getSemantics(button);

      expect(node.label, 'Notifications, 2 unread items');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        tester.getSemantics(find.byKey(UserMenuButton.avatarKey)).label,
        'Reader, Profile',
      );

      final focus = _focusButton(tester, button);
      await tester.pump();
      expect(focus.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(UserMenuPanel), findsOneWidget);
      expect(find.byKey(const ValueKey('user-menu-tab-profile')), findsNothing);
      expect(find.byTooltip('Likes'), findsOneWidget);
      expect(find.byTooltip('Replies'), findsOneWidget);
      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsOneWidget);
      expect(
        tester.widget<UserMenuPanel>(find.byType(UserMenuPanel)).view,
        UserMenuView.profile,
      );
      expect(find.text('Summary'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Preferences'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(UserMenuPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.byKey(const ValueKey('user-menu-tab-all')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}

FocusNode _focusButton(WidgetTester tester, Finder button) {
  final focusChild = find
      .descendant(of: button, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  return focus;
}
