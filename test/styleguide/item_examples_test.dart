import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/item_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all Item examples render at reference and narrow RTL large-text sizes',
    (tester) async {
      for (final scale in [1.0, 2.0]) {
        for (final example in itemExamples.examples) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: Directionality(
                    textDirection: scale == 1
                        ? TextDirection.ltr
                        : TextDirection.rtl,
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: scale == 1 ? 640 : 260,
                        child: Builder(builder: example.builder),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: '${example.title} at $scale',
          );
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );
  testWidgets(
    'accepted dropdown selects a person, dismisses, and restores focus',
    (tester) async {
      final example = itemExamples.examples.singleWhere(
        (e) => e.title == 'Dropdown',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('shadcn@vercel.com'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('maxleiter')),
        matchesSemantics(
          label: 'maxleiter, maxleiter@vercel.com',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(find.text('maxleiter'));
      await tester.pumpAndSettle();
      expect(find.text('Selected maxleiter'), findsOneWidget);
      expect(find.text('shadcn@vercel.com'), findsNothing);
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Select'))
            .focusNode
            ?.hasFocus,
        isTrue,
      );
    },
  );
}
