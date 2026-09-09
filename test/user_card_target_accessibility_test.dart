import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
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
        expect(find.byType(DHoverCardContent), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DHoverCardContent),
            matching: find.bySemanticsLabel('Profilee'),
          ),
          findsNothing,
        );

        await tester.sendKeyEvent(activation.key);
        await tester.pumpAndSettle();

        expect(api.cardsRequested, ['profilee']);
        expect(find.byType(DHoverCardContent), findsNothing);
        expect(find.text('@profilee'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'mouse hover loads a visual preview without changing the action',
    (tester) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      const profile = UserCard(
        username: 'profilee',
        name: 'Profilee',
        title: 'Community guide',
        location: 'Paris',
      );
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
                body: Center(
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
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.text('Profilee')));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        expect(api.cardsRequested, ['profilee']);
        expect(find.byType(DHoverCardContent), findsOneWidget);
        expect(find.text('Community guide'), findsOneWidget);
        expect(find.text('Paris'), findsOneWidget);
        expect(find.bySemanticsLabel('Community guide'), findsNothing);
        expect(
          find.bySemanticsLabel('View profile for @profilee'),
          findsOneWidget,
        );
        await mouse.removePointer();
      } finally {
        semantics.dispose();
      }
    },
  );
}
