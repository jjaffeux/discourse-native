import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/date_picker_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Date Picker registers the complete frozen example matrix', () {
    expect(componentExamples['date-picker'], same(datePickerExamples));
    expect(datePickerExamples.examples.map((example) => example.title), [
      'Composition',
      'Basic',
      'Range Picker',
      'Date of Birth',
      'Input',
      'Time Picker',
      'Natural Language Picker',
      'RTL',
    ]);
  });

  testWidgets('Date Picker examples fit narrow 200 percent text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 900);
    addTearDown(tester.view.reset);
    for (final example in datePickerExamples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 900),
                textScaler: TextScaler.linear(2),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(8),
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
      await tester.pump();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });

  testWidgets('input examples compose final shared owners', (tester) async {
    final example = datePickerExamples.examples.singleWhere(
      (example) => example.title == 'Input',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Builder(builder: example.builder)),
      ),
    );
    expect(find.byType(DInputGroup), findsOneWidget);
    expect(find.byType(DInputGroupInput), findsOneWidget);
    expect(find.byType(DPopover), findsOneWidget);
  });
}
