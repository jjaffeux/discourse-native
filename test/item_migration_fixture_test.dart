import 'package:discourse_native/item_review_main.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'production fixture preserves tag navigation and assignment edit permissions through RTL large text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const ItemMigrationFixture()),
      );
      await tester.tap(find.text('development'));
      await tester.pump();
      expect(find.text('Opened tag development'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Topic assigned to Sam'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Topic assigned to Sam'));
      await tester.pump();
      expect(find.text('Edit assignment 1'), findsOneWidget);
      await tester.tap(find.text('Editing allowed'));
      await tester.pump();
      await tester.tap(find.text('Topic assigned to Sam'));
      await tester.pump();
      expect(find.text('Edit assignment 1'), findsOneWidget);
      expect(find.text('Read only'), findsOneWidget);
      await tester.tap(find.text('LTR'));
      await tester.pump();
      await tester.tap(find.text('100%'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('fixture-assignment-3')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('This third line must remain visible.'),
        findsWidgets,
      );
    },
  );
}
