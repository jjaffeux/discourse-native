import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  for (final activation in [
    (name: 'Enter', key: LogicalKeyboardKey.enter),
    (name: 'Space', key: LogicalKeyboardKey.space),
  ]) {
    testWidgets('the compact profile target opens from ${activation.name}', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      const profile = UserCard(username: 'profilee', name: 'Profilee');
      final api = FakeDiscourseApi(
        user: reader,
        totals: const NotificationTotals(),
        cards: const {'profilee': profile},
      );
      final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
      final controller = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.example').copyWith(user: reader),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );
      await controller.load();
      addTearDown(controller.dispose);

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
              home: const Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: UserCardTarget(
                    username: 'profilee',
                    siteUrl: _siteUrl,
                    child: Text('Profilee'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final target = find.bySemanticsLabel('View profile for @profilee');
        expect(target, findsOneWidget);
        // Names and avatars are intentionally compact inline targets. They
        // still need the complete native focus and keyboard action path.
        expect(tester.getSize(target).height, lessThan(44));
        expect(
          tester.getSemantics(target),
          isSemantics(
            label: 'View profile for @profilee',
            isButton: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        final ink = find.descendant(of: target, matching: find.byType(InkWell));
        expect(ink, findsOneWidget);
        expect(
          tester.widget<InkWell>(ink).mouseCursor,
          SystemMouseCursors.click,
        );
        expect(tester.widget<InkWell>(ink).hoverColor, Colors.transparent);
        expect(
          tester.widget<InkWell>(ink).focusColor,
          Theme.of(tester.element(target)).shell.hover,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(target),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(activation.key);
        await tester.pumpAndSettle();

        expect(api.cardsRequested, ['profilee']);
        expect(find.text('@profilee'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });
  }
}
