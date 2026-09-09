import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/command_review_main.dart';

void main() {
  testWidgets(
    'review fixture changes inherited state while Dialog stays open',
    (tester) async {
      await tester.pumpWidget(const CommandReviewApp());
      await tester.pumpAndSettle();

      final trigger = find.text('Open live-update palette');
      await tester.ensureVisible(trigger);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(find.text('Change while open'), findsOneWidget);

      Future<void> select(String label) async {
        final row = find.text(label);
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.text('Change while open'), findsOneWidget);
      }

      await select('Toggle light / Plum radius');
      var context = tester.element(find.text('Change while open'));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(DTokens.of(context).radius, 12);

      await select('Toggle app / mono font');
      context = tester.element(find.text('Change while open'));
      expect(
        Theme.of(context).textTheme.bodyMedium?.fontFamily,
        'JetBrains Mono',
      );

      await select('Toggle LTR / RTL');
      context = tester.element(find.text('Change while open'));
      expect(Directionality.of(context), TextDirection.rtl);

      await select('Toggle 100% / 200% text');
      context = tester.element(find.text('Change while open'));
      expect(MediaQuery.textScalerOf(context).scale(10), 20);

      await select('Toggle motion preference');
      context = tester.element(find.text('Change while open'));
      expect(MediaQuery.disableAnimationsOf(context), isTrue);

      final close = find.text('Close live-update palette');
      await tester.ensureVisible(close);
      await tester.pump();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Change while open'), findsNothing);
    },
  );
}
