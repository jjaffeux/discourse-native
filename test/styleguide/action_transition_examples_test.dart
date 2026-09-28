import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/action_transition_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final example in actionTransitionExamples.examples) {
    testWidgets('${example.title} shows, replaces and hides actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );
      final transition = find.byType(DActionTransition);
      final action = find.descendant(
        of: transition,
        matching: find.byType(DButton),
      );
      expect(action, findsOneWidget);
      await tester.tap(find.text('Hide action'));
      await tester.pumpAndSettle();
      expect(action, findsNothing);
      await tester.tap(find.text('Show New topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show Reply'));
      await tester.pumpAndSettle();
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
