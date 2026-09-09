import 'package:discourse_native/src/styleguide/examples/native_select_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
