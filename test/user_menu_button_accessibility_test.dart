import 'dart:ui' show SemanticsAction;

import 'package:discourse_native/discourse_ui.dart';
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
  for (final (totals, role) in [
    (const NotificationTotals(unreadNotifications: 128), 'unread'),
    (
      const NotificationTotals(unreadNotifications: 126, unseenReviewables: 2),
      'review',
    ),
    (
      const NotificationTotals(
        unreadNotifications: 125,
        unseenReviewables: 2,
        unreadPersonalMessages: 1,
      ),
      'personal',
    ),
  ]) {
    testWidgets('bell capsule follows core $role color priority', (
      tester,
    ) async {
      const user = DiscourseUser(id: 7, username: 'reader');
      final controller = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.example').copyWith(user: user),
        ]),
        api: FakeDiscourseApi(user: user, totals: totals),
        authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );
      await controller.load();
      await controller.accountActivity.refresh(controller.currentInstance!);
      addTearDown(controller.dispose);
      final theme = AppTheme.light.copyWith(platform: TargetPlatform.macOS);
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: theme,
            home: const Scaffold(body: Center(child: UserMenuButton())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<DButton>(find.byKey(UserMenuButton.bellKey));
      final color = switch (role) {
        'personal' => theme.discourse.success,
        'review' => theme.colorScheme.error,
        _ => theme.discourse.notificationIndicator,
      };
      expect(button.backgroundColor, color.withValues(alpha: .14));
      expect(find.text('99+'), findsOneWidget);
      expect(button.semanticLabel, 'Notifications, 128 unread items');
    });
  }

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
      expect(tester.getSize(button).height, 28);
      expect(tester.getSize(button).width, greaterThan(28));
      expect(
        tester.getRect(button).right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(UserMenuButton.avatarKey)).left,
        ),
      );
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
      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        find.descendant(
          of: find.byType(UserMenuPanel),
          matching: find.byType(DTooltip),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('user-menu-tab-profile')), findsNothing);
      expect(find.byKey(const ValueKey('user-menu-tab-likes')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('user-menu-tab-replies')),
        findsOneWidget,
      );
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        tester.getSemantics(find.byKey(UserMenuButton.avatarKey)).id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byType(DDropdownMenuContent), findsOneWidget);
      expect(tester.widget<DButton>(button).focusNode!.hasFocus, isFalse);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.byKey(const ValueKey('user-menu-tab-all')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Disconnect'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        contains('Preferences'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byType(DDropdownMenuContent), findsNothing);
      expect(
        tester
            .widget<DButton>(find.byKey(UserMenuButton.avatarKey))
            .focusNode!
            .hasPrimaryFocus,
        isTrue,
      );
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
