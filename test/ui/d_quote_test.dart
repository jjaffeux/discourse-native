import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/quote_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pixel_samples.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('mark stays inset and follows $direction', (tester) async {
      const boundary = ValueKey('quote-pixels');
      final theme = AppTheme.light;
      final tokens = theme.extension<DTokens>()!;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: boundary,
                  child: ColoredBox(
                    color: tokens.background,
                    child: const SizedBox(
                      width: 240,
                      child: DQuote(child: SizedBox(height: 80)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final height = tester.getSize(find.byType(DQuote)).height;
      double x(double start) =>
          direction == TextDirection.ltr ? start : 240 - start;
      final pixels = await samplePixels(tester, find.byKey(boundary), [
        Offset(x(12), 30),
        Offset(x(12), 5),
        Offset(x(12), height - 5),
        Offset(x(2), 30),
        Offset(x(2), 2),
      ]);
      expect(pixels, [
        tokens.primary,
        tokens.muted,
        tokens.muted,
        tokens.muted,
        tokens.background,
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('quote styleguide examples fit narrow scaled RTL', (
    tester,
  ) async {
    for (final example in quoteExamples.examples) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: 280,
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
  });

  testWidgets(
    'decorations are inert and a trailing Native action keeps its bounds',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var removals = 0;
        const actionKey = ValueKey('remove-quote');
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    child: DQuote(
                      header: const Text('Source'),
                      trailing: DButton.iconOnly(
                        key: actionKey,
                        size: DButtonSize.tabAction,
                        tooltip: 'Remove quote',
                        semanticLabel: 'Remove quote',
                        icon: const DIcon(DIcons.xmark),
                        onPressed: () => removals++,
                      ),
                      child: const Text('Quoted content'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final action = find.byKey(actionKey);
        expect(
          tester.getSemantics(action),
          isSemantics(
            label: 'Remove quote',
            isButton: true,
            hasTapAction: true,
          ),
        );
        final rect = tester.getRect(action);
        await tester.tapAt(rect.centerLeft - const Offset(1, 0));
        await tester.pump();
        expect(removals, 0);
        await tester.tapAt(rect.center);
        await tester.pump();
        expect(removals, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(removals, 2);
        final quoteSign = find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.quoteRight,
        );
        expect(
          find.ancestor(of: quoteSign, matching: find.byType(ExcludeSemantics)),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
