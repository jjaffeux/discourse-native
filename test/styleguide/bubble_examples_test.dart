import 'package:discourse_native/src/styleguide/examples/bubble_examples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    WidgetBuilder builder, {
    double width = 640,
    double scale = 1,
    TextDirection direction = TextDirection.ltr,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('every frozen example renders narrow, scaled and RTL', (
    tester,
  ) async {
    for (final example in bubbleExamples.examples) {
      await tester.pumpWidget(
        host(
          example.builder,
          width: 280,
          scale: 2,
          direction: TextDirection.rtl,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });

  testWidgets('button and link examples run their real callbacks', (
    tester,
  ) async {
    final example = bubbleExamples.examples.singleWhere(
      (value) => value.title == 'Links and buttons',
    );
    await tester.pumpWidget(host(example.builder));

    await tester.ensureVisible(find.text('I forgot my password'));
    await tester.tap(find.text('I forgot my password'));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('bubble-action-result')))
          .data,
      'I forgot my password',
    );
    await tester.ensureVisible(find.text('Open the help center'));
    await tester.tap(find.text('Open the help center'));
    await tester.pump();
    expect(find.text('Help center link'), findsOneWidget);
  });

  testWidgets('reaction selection and error controls expose visible state', (
    tester,
  ) async {
    final example = bubbleExamples.examples.singleWhere(
      (value) => value.title == 'Reactions',
    );
    await tester.pumpWidget(host(example.builder));

    expect(find.text('👍 4 ✓'), findsOneWidget);
    await tester.ensureVisible(find.text('👍 4 ✓'));
    await tester.tap(find.text('👍 4 ✓'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('👍 3'), findsOneWidget);
    await tester.ensureVisible(find.text('Fail'));
    await tester.tap(find.text('Fail'));
    await tester.pump();
    expect(find.text('Reaction failed. Try again.'), findsOneWidget);
    expect(find.text('Retry !'), findsOneWidget);
  });

  testWidgets('collapsible example toggles complete long content', (
    tester,
  ) async {
    final example = bubbleExamples.examples.singleWhere(
      (value) => value.title == 'Show more / Collapsible',
    );
    await tester.pumpWidget(host(example.builder));

    expect(find.text('Show more'), findsOneWidget);
    await tester.tap(find.text('Show more'));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
    expect(
      find.textContaining('The dialog and drawer are fine'),
      findsOneWidget,
    );
  });

  testWidgets('prepared Popover composition opens real error details', (
    tester,
  ) async {
    final example = bubbleExamples.examples.singleWhere(
      (value) => value.title == 'Popover',
    );
    await tester.pumpWidget(host(example.builder));

    await tester.ensureVisible(find.byTooltip('Show error details'));
    await tester.tap(find.byTooltip('Show error details'));
    await tester.pumpAndSettle();
    expect(find.text('Command failed with exit code 1'), findsOneWidget);
    expect(find.textContaining('ENOENT:'), findsOneWidget);
  });
}
