import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final direction in TextDirection.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'profile sheet is inset and aligned on $platform, $direction, ${scale}x',
          (tester) async {
            final phone = Size(scale == 1 ? 430 : 320, 800);
            tester.view.physicalSize = phone;
            tester.view.devicePixelRatio = 1;
            tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
            tester.view.viewPadding = const FakeViewPadding(
              top: 59,
              bottom: 34,
            );
            addTearDown(tester.view.reset);
            const user = DiscourseUser(
              id: 7,
              username: 'reader',
              hidePresence: false,
              draftCount: 53,
            );
            const config = SiteConfig(userStatusEnabled: true);
            final controller = ShellController(
              instanceStore: FakeInstanceStore([
                instance('meta.example').copyWith(user: user, config: config),
              ]),
              api: FakeDiscourseApi(
                user: user,
                siteConfigs: const {'https://meta.example': config},
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
                  theme: (scale == 1 ? AppTheme.light : AppTheme.dark).copyWith(
                    platform: platform,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: Directionality(
                      textDirection: direction,
                      child: child!,
                    ),
                  ),
                  home: const Scaffold(
                    body: SafeArea(
                      child: Align(
                        alignment: AlignmentDirectional.topEnd,
                        child: UserMenuButton(),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final avatar = find.byKey(UserMenuButton.avatarKey);
            await tester.tap(avatar);
            await tester.pumpAndSettle();

            final sheet = find.byType(DSheetContent);
            final bounds = tester.getRect(sheet);
            expect(bounds.left, DSpacing.md);
            expect(bounds.right, phone.width - DSpacing.md);
            expect(bounds.bottom, phone.height - 34 - DSpacing.md);
            expect(bounds.top, closeTo(phone.height * .11, .01));
            final surface = tester.widget<Material>(
              find.descendant(of: sheet, matching: find.byType(Material)).first,
            );
            expect(surface.borderRadius, BorderRadius.circular(DRadius.panel));
            expect(surface.clipBehavior, Clip.antiAlias);
            expect(
              surface.color,
              DTokens.of(tester.element(sheet)).background.withValues(alpha: 1),
            );

            double start(Rect rect) =>
                direction == TextDirection.ltr ? rect.left : rect.right;
            final headerBounds = tester.getRect(find.byType(DSheetHeader));
            final close = find.byTooltip('Close');
            expect(close.hitTestable(), findsOneWidget);
            final rows = [
              ('Set a custom status', 'user-menu-row-user-status'),
              ('Online', 'user-menu-hide-presence'),
              ('Pause notifications', 'pause-notifications-row'),
              ('Summary', 'user-menu-row-summary'),
              ('Activity', 'user-menu-row-activity'),
              ('Drafts', 'user-menu-row-drafts'),
              ('Preferences', 'user-menu-row-preferences'),
              ('About', 'user-menu-row-about'),
              ('Disconnect', 'user-menu-row-disconnect'),
            ];
            double? labelStart;
            double? iconStart;
            for (final (label, key) in rows) {
              final row = find.byKey(ValueKey(key));
              await tester.ensureVisible(row);
              await tester.pumpAndSettle();
              expect(row.hitTestable(), findsOneWidget);
              final textRect = tester.getRect(find.text(label));
              final iconRect = tester.getRect(
                find.descendant(of: row, matching: find.byType(DIcon)).first,
              );
              labelStart ??= start(textRect);
              iconStart ??= start(iconRect);
              // Toggle's resting border contributes half a logical pixel.
              expect(start(textRect), closeTo(labelStart, .51), reason: label);
              expect(start(iconRect), closeTo(iconStart, .51), reason: label);
              expect(iconRect.center.dy, closeTo(textRect.center.dy, .01));
              expect(tester.getRect(find.byType(DSheetHeader)), headerBounds);
              if (label == 'Drafts') {
                final count = tester.getRect(find.text('53'));
                expect(count.center.dy, closeTo(textRect.center.dy, .01));
                if (direction == TextDirection.ltr) {
                  expect(count.left, greaterThan(textRect.right));
                } else {
                  expect(count.right, lessThan(textRect.left));
                }
              }
            }
            expect(start(tester.getRect(find.text('Profile'))), iconStart);
            expect(tester.takeException(), isNull);

            await tester.tap(close);
            await tester.pumpAndSettle();
            expect(sheet, findsNothing);
            await tester.tap(avatar);
            await tester.pumpAndSettle();
            await tester.drag(find.byType(DSheetTitle), const Offset(0, 500));
            await tester.pumpAndSettle();
            expect(sheet, findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
