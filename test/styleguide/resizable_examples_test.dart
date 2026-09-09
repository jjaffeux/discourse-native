import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/resizable_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all examples mount production components across themes, direction and large text',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final direction in TextDirection.values) {
          for (final example in resizableExamples.examples) {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: Directionality(
                    textDirection: direction,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(2),
                        disableAnimations: true,
                      ),
                      child: SingleChildScrollView(
                        child: SizedBox(
                          width: 320,
                          child: Builder(builder: example.builder),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(
              find.byType(DResizableHandle),
              findsWidgets,
              reason: example.title,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${example.title} $direction ${theme.brightness}',
            );
          }
        }
      }
    },
  );
  testWidgets('iOS production adapters provide 48px transparent drag regions', (
    tester,
  ) async {
    for (final example in resizableExamples.examples.where(
      (e) => e.title.startsWith('Production'),
    )) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: SizedBox(
              width: 640,
              child: Builder(builder: example.builder),
            ),
          ),
        ),
      );
      for (final handle in find.byType(DResizableHandle).evaluate()) {
        expect(
          tester.getSize(find.byWidget(handle.widget)).width,
          greaterThanOrEqualTo(48),
          reason: example.title,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'controlled example supports collapse, restore and dynamic panels',
    (tester) async {
      final example = resizableExamples.examples.firstWhere(
        (e) => e.title.startsWith('Controlled'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) => example.builder(context)),
          ),
        ),
      );
      await tester.tap(find.text('Collapse'));
      await tester.pump();
      expect(find.textContaining('left: 0px'), findsOneWidget);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      expect(find.textContaining('left: 0px'), findsNothing);
      await tester.tap(find.text('Remove middle'));
      await tester.pump();
      expect(find.text('Fixed'), findsNothing);
      await tester.tap(find.text('Insert middle'));
      await tester.pump();
      expect(find.text('Fixed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
