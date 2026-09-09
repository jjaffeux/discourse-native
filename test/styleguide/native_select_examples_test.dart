import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/native_select_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reference state examples match the official option sets', (
    tester,
  ) async {
    Future<DNativeSelect<String>> buildReference(String title) async {
      final example = nativeSelectExamples.examples.singleWhere(
        (candidate) => candidate.title == title,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );
      return tester.widget(find.byType(DNativeSelect<String>));
    }

    final disabled = await buildReference('Reference disabled');
    expect(disabled.placeholder, 'Select priority');
    expect(disabled.onChanged, isNull);
    expect(
      disabled.entries.whereType<DNativeSelectOption<String>>().map(
        (option) => (option.value, option.label),
      ),
      const [
        ('low', 'Low'),
        ('medium', 'Medium'),
        ('high', 'High'),
        ('critical', 'Critical'),
      ],
    );

    final invalid = await buildReference('Reference invalid');
    expect(invalid.placeholder, 'Select role');
    expect(invalid.invalid, isTrue);
    expect(
      invalid.entries.whereType<DNativeSelectOption<String>>().map(
        (option) => (option.value, option.label),
      ),
      const [
        ('admin', 'Admin'),
        ('editor', 'Editor'),
        ('viewer', 'Viewer'),
        ('guest', 'Guest'),
      ],
    );
  });

  testWidgets(
    'all examples fit a narrow RTL large-text preview in both themes',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final example in nativeSelectExamples.examples) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
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
          expect(tester.takeException(), isNull, reason: example.title);
        }
      }
    },
  );
}
