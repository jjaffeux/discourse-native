import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance() + .05;
  final second = b.computeLuminance() + .05;
  return first > second ? first / second : second / first;
}

void main() {
  test('code remains readable and outlined on every preset in both modes', () {
    for (final preset in forumThemePresets) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.fromPalette(preset.resolve(brightness));
        final tokens = theme.extension<DTokens>()!;
        final bubble = Color.lerp(tokens.background, tokens.foreground, .06)!;
        final reason = '${preset.id} ${brightness.name}';
        expect(
          contrast(tokens.foreground, tokens.inlineCodeBackground),
          greaterThanOrEqualTo(4.5),
          reason: reason,
        );
        expect(
          contrast(tokens.inlineCodeBorder, bubble),
          greaterThan(1.2),
          reason: reason,
        );
        expect(
          contrast(tokens.inlineCodeBackground, bubble),
          greaterThan(contrast(theme.code.inlineBackground, bubble)),
          reason: reason,
        );
      }
    }
  });

  testWidgets(
    'cooked code follows palette changes with compact spacing and links',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: SizedBox(
                width: 280,
                child: CookedHtml(
                  html:
                      '<p>Try <a href="https://example.com"><code>a  b</code></a> '
                      'and <code>max_parallel_maintenance_workers</code>.</p>',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tokens = theme.extension<DTokens>()!;
        final chip = find.descendant(
          of: find.byType(InlineCode).first,
          matching: find.byType(DText),
        );
        expect(chip, findsOneWidget);
        final text = tester.widget<Text>(
          find.descendant(of: chip, matching: find.byType(Text)),
        );
        expect(text.data, 'a  b');
        expect(text.style!.color, theme.colorScheme.primary);
        expect(text.style!.fontSize, DiscourseTypography.base * 0.875);
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: chip,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(decoration.color, tokens.inlineCodeBackground);
        expect(decoration.border, Border.all(color: tokens.inlineCodeBorder));
        final padding = tester.widget<Padding>(
          find.descendant(of: chip, matching: find.byType(Padding)),
        );
        expect(
          padding.padding,
          const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
