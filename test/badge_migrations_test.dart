import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/component_review/badge_fixtures.dart';
import '../tool/component_review/badge_main.dart';

void main() {
  testWidgets(
    'root profile review actually scales the real popup badges to 200 percent',
    (tester) async {
      final controller = await createBadgeFixtureController();
      try {
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: BadgeReviewApp(
              controller: controller,
              largeProfile: true,
              onReturn: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open staff profile'));
        await tester.pumpAndSettle();
        final staff = find.text('staff');
        final count = find.text('123 badges');
        expect(staff, findsOneWidget);
        expect(count, findsOneWidget);
        expect(MediaQuery.textScalerOf(tester.element(staff)).scale(12), 24);
        expect(MediaQuery.textScalerOf(tester.element(count)).scale(12), 24);
        expect(
          tester
              .getSize(find.ancestor(of: staff, matching: find.byType(DBadge)))
              .height,
          greaterThanOrEqualTo(36),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'real status and Chat count fixtures preserve full accessible counts and profile data',
    (tester) async {
      final controller = await createBadgeFixtureController();
      final semantics = tester.ensureSemantics();
      try {
        for (final theme in [
          AppTheme.light,
          StyleguideTheme.plum.resolve(AppTheme.light),
        ]) {
          await tester.pumpWidget(
            ShellScope(
              controller: controller,
              child: MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: SizedBox(
                      width: 360,
                      child: BadgeMigrationFixtures(controller: controller),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('99+'), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp('123 urgent notifications')),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel('123 unread posts'), findsOneWidget);
          expect(find.byType(DBadge), findsWidgets);
        }
        await tester.tap(find.text('Open staff profile'));
        await tester.pumpAndSettle();
        expect(find.text('staff'), findsOneWidget);
        expect(find.text('123 badges'), findsOneWidget);
        expect(
          find.ancestor(of: find.text('staff'), matching: find.byType(DBadge)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        semantics.dispose();
      }
    },
  );
}
