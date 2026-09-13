import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final width in [320.0, 900.0]) {
    for (final dark in [false, true]) {
      testWidgets('separate menus fit width $width, dark $dark at 200% text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const user = DiscourseUser(
          id: 7,
          username: 'reader',
          name: 'Reader',
          canInviteToForum: true,
        );
        final controller = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.example').copyWith(user: user),
          ]),
          api: FakeDiscourseApi(
            user: user,
            totals: const NotificationTotals(unreadNotifications: 3),
          ),
          authenticator: FakeAuthenticator()
            ..keys['https://meta.example'] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
        );
        await controller.load();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
                platform: TargetPlatform.macOS,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
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
        for (final key in [UserMenuButton.bellKey, UserMenuButton.avatarKey]) {
          await tester.tap(find.byKey(key));
          await tester.pumpAndSettle();
          final surface = key == UserMenuButton.bellKey
              ? find.byType(UserMenuPanel)
              : find.byType(DDropdownMenuContent);
          expect(surface, findsOneWidget);
          final rect = tester.getRect(surface);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.bottom, lessThanOrEqualTo(800));
          if (key == UserMenuButton.bellKey) {
            final badges = find.descendant(
              of: surface,
              matching: find.byType(DBadge),
            );
            expect(badges, findsWidgets);
            final colors = Theme.of(tester.element(surface)).discourse;
            for (final badge in badges.evaluate()) {
              final badgeFinder = find.byWidget(badge.widget);
              final decoration =
                  tester
                          .widget<AnimatedContainer>(
                            find
                                .descendant(
                                  of: badgeFinder,
                                  matching: find.byType(AnimatedContainer),
                                )
                                .first,
                          )
                          .decoration!
                      as BoxDecoration;
              expect(decoration.color, colors.notificationIndicator);
              expect(tester.getSize(badgeFinder).height, 30);
            }
          }
        }
        await tester.tapAt(const Offset(15, 760));
        await tester.pumpAndSettle();
        expect(find.byType(UserMenuPanel), findsNothing);
        expect(find.byType(DDropdownMenuContent), findsNothing);
      });
    }
  }
}
