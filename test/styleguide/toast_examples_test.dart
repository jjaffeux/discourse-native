import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/toast_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Toast registers every frozen section as real public API examples', () {
    expect(componentExamples['toast'], same(toastExamples));
    expect(toastExamples.examples, hasLength(5));
    expect(toastExamples.status.name, 'implemented');
    expect(
      toastExamples.examples.every(
        (example) => example.code.contains('DToast'),
      ),
      isTrue,
    );
  });

  for (var index = 0; index < toastExamples.examples.length; index++) {
    testWidgets(
      '${toastExamples.examples[index].title} fits 280px RTL at 200% in custom theme',
      (tester) async {
        await _pump(tester, index, width: 280, scale: 2);
        expect(find.byType(DButton), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('types render all icons and persistent loading', (tester) async {
    await _pump(tester, 1);
    for (final label in [
      'Default',
      'Success',
      'Info',
      'Warning',
      'Error',
      'Loading',
    ]) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(find.byType(DSpinner), findsOneWidget);
    expect(find.text('Creating event…'), findsOneWidget);
    expect(find.text('The event could not be created.'), findsOneWidget);
  });

  testWidgets('promise succeeds, errors, and ignores a replaced id', (
    tester,
  ) async {
    await _pump(tester, 2);
    await tester.tap(find.text('Resolve promise'));
    await tester.pump();
    expect(find.text('Creating event…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Event created.'), findsOneWidget);

    await tester.tap(find.text('Reject promise'));
    await tester.pump();
    await tester.tap(find.text('Replace id'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(
      find.text('The pending result no longer owns this notice.'),
      findsOneWidget,
    );
    expect(find.text('Could not create event.'), findsNothing);
  });

  testWidgets(
    'stack is limited, repeated ids update, and custom content closes',
    (tester) async {
      await _pump(tester, 3);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Add notice'));
        await tester.pump();
      }
      expect(find.textContaining('Notice'), findsNWidgets(3));
      await tester.tap(find.text('Update sync'));
      await tester.pump();
      await tester.tap(find.text('Update sync'));
      await tester.pump();
      expect(find.text('Synchronized revision 7'), findsOneWidget);
      expect(find.textContaining('Synchronized revision'), findsOneWidget);
      await tester.tap(find.text('Custom'));
      await tester.pump();
      expect(find.text('A custom composed notification'), findsOneWidget);
      final customToast = find.ancestor(
        of: find.text('A custom composed notification'),
        matching: find.byType(Dismissible),
      );
      await tester.tap(
        find.descendant(
          of: customToast,
          matching: find.byTooltip('Close toast'),
        ),
      );
      await tester.pump();
      expect(find.text('A custom composed notification'), findsNothing);
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  int index, {
  double width = 600,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: StyleguideTheme.plum.resolve(AppTheme.light),
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: 700,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 700),
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: DToaster(
                child: SingleChildScrollView(
                  child: Builder(
                    builder: toastExamples.examples[index].builder,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
