import 'package:discourse_native/src/styleguide/examples/progress_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all progress compositions fit narrow scaled RTL and live palettes',
    (tester) async {
      for (final example in progressExamples.examples) {
        for (final theme in [
          AppTheme.light,
          AppTheme.dark,
          StyleguideTheme.forest.resolve(AppTheme.light),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(2),
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
          expect(tester.takeException(), isNull, reason: example.title);
        }
      }
    },
  );
  testWidgets(
    'controlled example responds to keyboard and retains value through theme changes',
    (tester) async {
      final example = progressExamples.examples.firstWhere(
        (e) => e.title == 'Controlled',
      );
      Future<void> pump(ThemeData theme) => tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: Builder(builder: example.builder)),
        ),
      );
      await pump(AppTheme.light);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('40%'), findsOneWidget);
      await pump(AppTheme.dark);
      await tester.pumpAndSettle();
      expect(find.text('40%'), findsOneWidget);
      await tester.tap(find.text('Unknown / resume'));
      await tester.pump();
      expect(find.text('—'), findsOneWidget);
      await tester.tap(find.text('Unknown / resume'));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsOneWidget);
    },
  );
}
