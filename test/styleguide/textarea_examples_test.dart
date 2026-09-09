import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/textarea_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all frozen Textarea examples are registered', () {
    expect(componentExamples['textarea'], same(textareaExamples));
    expect(textareaExamples.status, ComponentStatus.implemented);
    expect(textareaExamples.examples.map((example) => example.title), [
      'Default',
      'Field',
      'Disabled',
      'Invalid',
      'Button and native Form',
      'RTL',
      'Bounded editing and read-only',
    ]);
  });
  testWidgets('actual examples support 216px 200 percent RTL and live themes', (
    tester,
  ) async {
    for (final example in textareaExamples.examples) {
      for (final theme in [
        StyleguideTheme.light,
        StyleguideTheme.dark,
        StyleguideTheme.forest,
        StyleguideTheme.plum,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.resolve(AppTheme.light),
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
                      width: 216,
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(DTextarea), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: '${example.title} ${theme.name}',
        );
      }
    }
  });
  testWidgets('form example validates saves and resets local state', (
    tester,
  ) async {
    final example = textareaExamples.examples.firstWhere(
      (e) => e.title == 'Button and native Form',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    await tester.tap(find.text('Send message'));
    await tester.pump();
    expect(find.text('Enter a message.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A local message');
    await tester.tap(find.text('Send message'));
    await tester.pump();
    expect(find.text('Saved: A local message'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('Saved: A local message'), findsNothing);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
  });
}
