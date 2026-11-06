import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/palette_contrast.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

DTokens _tokens({required Color text, required Color ground}) => DTokens(
  colors: ColorScheme.light(primary: const Color(0xff0000ff), onSurface: text),
  background: ground,
  surface: ground,
  muted: ground,
  border: ground,
  hover: ground,
  selected: ground,
  selectedForeground: text,
);

void main() {
  test('read-title ink matches independent mockup contrast fixtures', () {
    // From themeMixes at mockups 6373369, with blue accent, green success and
    // red danger. Neither mode can keep the initial 30% text share.
    final light = _tokens(text: Colors.black, ground: Colors.white);
    final dark = _tokens(text: Colors.white, ground: Colors.black);
    expect(light.titleRead.toARGB32(), 0xff5b5b5b);
    expect(dark.titleRead.toARGB32(), 0xff939393);
    expect(
      light
          .copyWith(
            background: Colors.black,
            surface: Colors.black,
            muted: Colors.black,
            hover: Colors.black,
            selected: Colors.black,
            colors: dark.colors,
          )
          .titleRead,
      dark.titleRead,
    );
    expect(light.lerp(dark, 1).titleRead, dark.titleRead);
  });

  test('read titles retain AA contrast across every supported palette', () {
    for (final preset in forumThemePresets) {
      for (final brightness in Brightness.values) {
        for (final tint in [0.0, .5, 1.0]) {
          final theme = AppTheme.fromPalette(
            preset.copyWith(tint: tint).resolve(brightness),
          );
          final tokens = theme.extension<DTokens>()!;
          // Check the rounded display color, independently of the token's
          // binary-search threshold and its safety margin.
          final title = Color(tokens.titleRead.toARGB32());
          for (final (name, under) in [
            ('ground', tokens.background),
            ('panel', tokens.panelBackground),
            ('raised', tokens.raisedBackground),
            ('floating', tokens.surface),
            ('muted', tokens.muted),
            ('selected', tokens.selected),
            ('selected row', tokens.selectionTint),
          ]) {
            expect(
              contrastRatio(title, Color.alphaBlend(under, tokens.background)),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${preset.id}, $brightness, tint=$tint, $name=$under, ink=$title, full=${tokens.foreground}',
            );
          }
          for (final under in [tokens.background, tokens.selectionTint]) {
            expect(
              contrastRatio(
                Color(tokens.mutedForeground.toARGB32()),
                Color.alphaBlend(under, tokens.background),
              ),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${preset.id}, $brightness, tint=$tint, muted unread title',
            );
          }
        }
      }
    }
  });

  testWidgets('selected Items preserve title contrast on a tinted palette', (
    tester,
  ) async {
    final preset = forumThemePresets.firstWhere((p) => p.id == 'grey-amber');
    final theme = AppTheme.fromPalette(
      preset.copyWith(tint: .5).resolve(Brightness.dark),
    );
    final tokens = theme.extension<DTokens>()!;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: DItem(
            selected: true,
            selectionStyle: DItemSelectionStyle.filled,
            showSelectionIndicator: false,
            onPressed: () {},
            children: [
              DItemContent(
                children: [
                  DItemTitle(
                    child: Text(
                      'Read topic',
                      style: TextStyle(color: tokens.titleRead),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final surface = tester.renderObject<RenderDecoratedBox>(
      find
          .descendant(
            of: find.byType(DItem),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final fill = (surface.decoration as BoxDecoration).color!;
    expect(fill.a, lessThan(.12));
    expect(
      contrastRatio(
        tokens.titleRead,
        Color.alphaBlend(fill, tokens.background),
      ),
      greaterThanOrEqualTo(4.5),
    );
  });
}
