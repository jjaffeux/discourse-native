import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/search_words.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/native_ui_evidence.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'searched text stays readable on a translucent background (dark: $dark)',
      (tester) async {
        await prepareNativeUiEvidence(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: nativeUiEvidenceBuilder,
            home: const DPageSurface(
              child: SearchWords(
                query: 'needle',
                child: CookedHtml(
                  html:
                      '<p>plain needle and <a href="https://example.com">linked needle</a></p>',
                  buildAsync: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final marked = <TextStyle>[];
        void visit(InlineSpan span, TextStyle inherited) {
          if (span is! TextSpan) return;
          final style = inherited.merge(span.style);
          if (span.text == 'needle') marked.add(style);
          for (final child in span.children ?? const <InlineSpan>[]) {
            visit(child, style);
          }
        }

        for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
          visit(rich.text, const TextStyle());
        }
        await captureNativeUi(tester, 'search-text-${dark ? 'dark' : 'light'}');
        expect(
          marked,
          hasLength(2),
          reason: 'plain and linked matches both render',
        );
        for (final style in marked) {
          final foreground = style.foreground?.color ?? style.color!;
          final background = style.background?.color ?? style.backgroundColor!;
          expect(background.a, closeTo(.13, .005));
          expect(foreground.a, 1);
          final context = tester.element(find.byType(CookedHtml));
          final canvas = DTokens.of(context).background;
          final painted = Color.alphaBlend(background, canvas);
          final high = foreground.computeLuminance();
          final low = painted.computeLuminance();
          final contrast = high > low
              ? (high + .05) / (low + .05)
              : (low + .05) / (high + .05);
          expect(
            contrast,
            greaterThanOrEqualTo(3),
            reason: 'a match remains legible against its painted background',
          );
        }
      },
    );
  }
}
