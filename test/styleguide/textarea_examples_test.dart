import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/textarea_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

StyleguideExample _example(String title) =>
    textareaExamples.examples.firstWhere((e) => e.title == title);

Widget _host(StyleguideExample example, {double width = 640}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: Builder(builder: example.builder),
      ),
    ),
  ),
);

void main() {
  test('all frozen Textarea examples are registered', () {
    expect(componentExamples['textarea'], same(textareaExamples));
    expect(textareaExamples.status, ComponentStatus.implemented);
    expect(textareaExamples.examples.map((example) => example.title), [
      'Default',
      'Field',
      'Disabled',
      'Invalid',
      'Button',
      'RTL',
      'Form',
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

  testWidgets(
    'Field example names and describes the editor and focuses it from the label',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(_example('Field')));
      final node = tester.getSemantics(find.byType(EditableText));
      expect(node.label, 'Message');
      expect(node.hint, 'Enter your message below.');
      expect(node.getSemanticsData().flagsCollection.isTextField, isTrue);
      final label = tester.getRect(find.text('Message'));
      final description = tester.getRect(
        find.text('Enter your message below.'),
      );
      final field = tester.getRect(find.byType(DTextarea));
      expect(description.top - label.bottom, 4);
      expect(field.top - description.bottom, 8);
      await tester.tap(find.text('Message'));
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'Button example stretches Send message under the field and sends its text',
    (tester) async {
      await tester.pumpWidget(_host(_example('Button')));
      final field = tester.getRect(find.byType(DTextarea));
      final button = tester.getRect(find.byType(DButton));
      expect(field.width, 640);
      expect(button.left, field.left);
      expect(button.right, field.right);
      expect(button.top - field.bottom, 8);
      await tester.enterText(find.byType(TextField), 'Hello there');
      await tester.tap(find.text('Send message'));
      await tester.pump();
      expect(find.text('Sent: Hello there'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
    },
  );

  testWidgets('RTL example keeps the 64px minimum inside the 320px maximum', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_example('RTL')));
    expect(tester.getSize(find.byType(DTextarea)).width, 320);
    expect(tester.getSize(find.byType(AnimatedContainer)).height, 64);
    expect(
      Directionality.of(tester.element(find.byType(TextField))),
      TextDirection.rtl,
    );
    expect(find.text('التعليقات'), findsOneWidget);
    expect(find.text('شاركنا أفكارك حول خدمتنا.'), findsOneWidget);
  });

  testWidgets('Form example validates saves and resets local state', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_example('Form')));
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
