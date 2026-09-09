import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/card_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all Card examples render at narrow 200 percent RTL', (
    tester,
  ) async {
    for (final example in cardExamples.examples) {
      await tester.pumpWidget(
        MaterialApp(
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
                    width: 260,
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('login validates locally and spacing retains draft', (
    tester,
  ) async {
    final example = cardExamples.examples.singleWhere(
      (e) => e.title == 'Shared spacing',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.tap(find.text('Login').last);
    await tester.pump();
    expect(find.text('Enter an email address'), findsOneWidget);
    expect(find.byType(DInput), findsNWidgets(2));
    expect(find.byType(DField), findsNWidgets(2));
    expect(find.byType(DToggleGroup<double>), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'local@example.com');
    await tester.enterText(find.byType(TextField).last, 'local-only');
    await tester.tap(find.text('32px'));
    await tester.pump();
    expect(
      tester
          .widget<DToggleGroup<double>>(find.byType(DToggleGroup<double>))
          .values,
      const [32],
    );
    expect(find.text('local@example.com'), findsOneWidget);
    await tester.ensureVisible(find.text('Login').last);
    await tester.tap(find.text('Login').last);
    await tester.pump();
    expect(find.text('Signed in locally'), findsOneWidget);
  });

  testWidgets(
    'login draft selection and focus survive narrow scaled RTL reflow',
    (tester) async {
      var width = 384.0;
      var scale = 1.0;
      var direction = TextDirection.ltr;
      var theme = ThemeData.light();
      late StateSetter update;
      final example = cardExamples.examples.singleWhere(
        (entry) => entry.title == 'Login',
      );

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: direction,
                    child: SizedBox(
                      width: width,
                      child: SingleChildScrollView(
                        child: Builder(builder: example.builder),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      final password = find.byType(TextField).last;
      await tester.enterText(find.byType(TextField).first, 'local@example.com');
      await tester.enterText(password, 'draft-password');
      final element = tester.element(password);
      final field = tester.widget<TextField>(password);
      field.controller!.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      field.focusNode!.requestFocus();
      await tester.pump();

      update(() {
        width = 260;
        scale = 2;
        direction = TextDirection.rtl;
        theme = ThemeData.dark();
      });
      await tester.pumpAndSettle();

      final reflowed = tester.widget<TextField>(find.byType(TextField).last);
      expect(tester.element(find.byType(TextField).last), same(element));
      expect(reflowed.controller, same(field.controller));
      expect(reflowed.controller!.text, 'draft-password');
      expect(
        reflowed.controller!.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8),
      );
      expect(reflowed.focusNode, same(field.focusNode));
      expect(reflowed.focusNode!.hasFocus, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'final owner variants and image badge match frozen compositions',
    (tester) async {
      final login = cardExamples.examples.singleWhere(
        (e) => e.title == 'Login',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: login.builder)),
        ),
      );
      final buttons = tester.widgetList<DButton>(find.byType(DButton)).toList();
      expect(
        buttons.any((button) => button.variant == DButtonVariant.link),
        true,
      );
      expect(
        buttons.any((button) => button.variant == DButtonVariant.outline),
        true,
      );
      expect(
        buttons.any((button) => button.variant == DButtonVariant.primary),
        true,
      );

      final image = cardExamples.examples.singleWhere(
        (e) => e.title == 'Image',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: image.builder)),
        ),
      );
      final badge = tester.widget<DBadge>(find.byType(DBadge));
      expect(badge.variant, DBadgeVariant.secondary);
    },
  );
}
