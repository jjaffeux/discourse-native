import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/empty_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('documented actions retain their reference button variants', (
    tester,
  ) async {
    Future<DButton> actionFor(String exampleTitle, String label) async {
      final example = emptyExamples.examples.singleWhere(
        (example) => example.title == exampleTitle,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );
      return tester.widget<DButton>(
        find.ancestor(of: find.text(label), matching: find.byType(DButton)),
      );
    }

    expect(
      (await actionFor('Basic', 'Create Project')).variant,
      DButtonVariant.primary,
    );
    expect(
      (await actionFor('Background', 'Refresh')).variant,
      DButtonVariant.outline,
    );
    final invite = await actionFor('Avatar Group', 'Invite Members');
    expect(invite.variant, DButtonVariant.primary);
    expect(invite.icon, isNotNull);
  });

  testWidgets(
    'every example fits narrow large-text RTL and wide dark previews',
    (tester) async {
      addTearDown(tester.view.reset);
      for (final wide in [false, true]) {
        tester.view.physicalSize = Size(wide ? 1000 : 320, 1000);
        tester.view.devicePixelRatio = 1;
        for (final example in emptyExamples.examples) {
          await tester.pumpWidget(
            MaterialApp(
              theme: wide ? ThemeData.dark() : ThemeData.light(),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(wide ? 1000 : 320, 1000),
                    textScaler: TextScaler.linear(wide ? 1 : 2),
                    disableAnimations: true,
                  ),
                  child: Directionality(
                    textDirection: wide ? TextDirection.ltr : TextDirection.rtl,
                    child: SingleChildScrollView(
                      child: Builder(
                        key: ValueKey(example.title),
                        builder: example.builder,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${example.title}, wide=$wide',
          );
        }
      }
    },
  );

  testWidgets(
    'search composition matches the reference and submits from input',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EmptySearchSample())),
      );

      final inputGroup = find.byType(DInputGroup);
      final input = find.byType(DInputGroupInput);
      final shortcut = find.descendant(
        of: inputGroup,
        matching: find.byType(DKbd),
      );
      final shortcutAddon = find.ancestor(
        of: shortcut,
        matching: find.byType(DInputGroupAddon),
      );
      expect(find.text('Search'), findsNothing);
      expect(shortcut, findsOneWidget);
      expect(
        tester.getRect(inputGroup).right - tester.getRect(shortcut).right,
        lessThan(16),
      );

      await tester.tap(shortcutAddon);
      await tester.pump();
      expect(
        tester.widget<DInputGroupInput>(input).focusNode!.hasFocus,
        isTrue,
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.text('Enter a search query.'), findsOneWidget);
      await tester.enterText(input, 'guide');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(find.text('No local pages match “guide”.'), findsOneWidget);
      await tester.tap(find.text('Contact support'));
      await tester.pump();
      expect(
        find.text('Support is available at help@example.test.'),
        findsOneWidget,
      );
    },
  );
}
