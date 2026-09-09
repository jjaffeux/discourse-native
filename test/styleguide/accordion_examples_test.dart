import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/accordion_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget exampleHost(String title, {double textScale = 1}) {
  final example = accordionExamples.examples.firstWhere(
    (item) => item.title == title,
  );
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: SingleChildScrollView(child: Builder(builder: example.builder)),
      ),
    ),
  );
}

void main() {
  test('Accordion is registered with every frozen example', () {
    expect(componentExamples['accordion'], same(accordionExamples));
    expect(
      accordionExamples.examples.map((example) => example.title),
      containsAll([
        'Basic',
        'Multiple',
        'Disabled',
        'Borders',
        'Card',
        'RTL',
        'Controlled and lifecycle',
      ]),
    );
    expect(
      accordionExamples.examples.every((example) => example.code.isNotEmpty),
      isTrue,
    );
  });

  for (final example in accordionExamples.examples) {
    testWidgets('${example.title} renders at 240px and 200% text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: 240,
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Multiple example opens two panels and disabled item stays closed',
    (tester) async {
      await tester.pumpWidget(exampleHost('Multiple'));
      expect(find.textContaining('Choose email alerts'), findsOneWidget);
      await tester.tap(find.text('Privacy & Security'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Choose email alerts'), findsOneWidget);
      expect(find.textContaining('Manage two-factor'), findsOneWidget);

      await tester.pumpWidget(exampleHost('Disabled'));
      await tester.tap(find.text('Premium feature information'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Upgrade your plan'), findsNothing);
    },
  );

  testWidgets(
    'controlled example preserves draft through reorder and collapse',
    (tester) async {
      await tester.pumpWidget(exampleHost('Controlled and lifecycle'));
      await tester.enterText(find.byType(TextField), 'Edited draft');
      await tester.tap(find.text('Reorder'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Edited draft',
      );
      await tester.tap(find.text('Profile draft'));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.text('Profile draft'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Edited draft',
      );
      await tester.tap(find.text('Security review'));
      await tester.pumpAndSettle();
      expect(find.text('Open: profile, security'), findsOneWidget);
      await tester.tap(find.text('Remove security'));
      await tester.pumpAndSettle();
      expect(find.text('Security review'), findsNothing);
      expect(find.text('Open: profile'), findsOneWidget);
      await tester.tap(find.text('Add security'));
      await tester.pumpAndSettle();
      expect(find.text('Security review'), findsOneWidget);
      expect(find.textContaining('Review recent sessions'), findsNothing);
    },
  );
}
