import 'package:discourse_native/src/styleguide/examples/message_scroller_examples.dart';
import 'package:discourse_native/src/ui/components/d_message_scroller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accounts for every frozen behavior family', () {
    final text = messageScrollerExamples.examples
        .expand(
          (example) => [example.title, example.description, ...example.states],
        )
        .join(' ')
        .toLowerCase();

    for (final term in const [
      'stream',
      'previous context',
      'anchor',
      'group',
      'saved',
      'no flash',
      'prepend',
      'visibility',
      'scroll state',
      'virtual',
      'accessibility',
      'unstyled',
      'reduced motion',
    ]) {
      expect(text, contains(term), reason: term);
    }
  });

  testWidgets('all examples render at narrow 200% RTL with reduced motion', (
    tester,
  ) async {
    for (final example in messageScrollerExamples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Builder(builder: example.builder),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });

  testWidgets('command example targets a stable virtualized row', (
    tester,
  ) async {
    final example = messageScrollerExamples.examples.singleWhere(
      (candidate) => candidate.title.startsWith('Commands'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 700, child: Builder(builder: example.builder)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Message 24'));
    await tester.pumpAndSettle();

    expect(find.text('Addressable message 24'), findsOneWidget);
    final viewport = tester.widget<DMessageScrollerViewport>(
      find.byType(DMessageScrollerViewport),
    );
    expect(viewport.itemId(23), 'command-23');
  });
}
