import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/d_icon_glyph.dart';
import 'package:discourse_native/src/theme/d_icon_sets.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as vg;

final class _Tint extends vg.ColorMapper {
  _Tint(this.color);

  final vg.Color color;

  @override
  vg.Color substitute(
    String? id,
    String elementName,
    String attributeName,
    vg.Color color,
  ) => this.color;
}

/// Every single-colour icon the app ships, in each icon family.
List<DIconData> _catalog() => [
  for (final icon in {...DIcons.byName.values, ...DNativeIcons.byName.values})
    if (!icon.preserveColors) icon,
  for (final set in DIconSet.values.skip(1))
    for (final name in DIcons.byName.keys)
      if (alternateIconSvg(set, name) case final svg?) DIconData(name, svg),
];

/// The colours flutter_svg compiles into [icon]'s picture for [tint], in the
/// order the picture paints them.
List<Color> _compiledColors(DIconData icon, Color tint) {
  final color = vg.Color(tint.toARGB32());
  final instructions = vg.parseWithoutOptimizers(
    icon.tintableSvg,
    theme: vg.SvgTheme(currentColor: color),
    colorMapper: _Tint(color),
  );
  return [
    for (final command in instructions.commands)
      if (command.paintId case final paintId?) ...[
        if (instructions.paints[paintId].fill case final fill?)
          Color(fill.color.value),
        if (instructions.paints[paintId].stroke case final stroke?)
          Color(stroke.color.value),
      ],
  ];
}

void main() {
  const tints = [
    Color(0xFF3A7BD5),
    Color(0x80E45735),
    Color(0xFF000000),
    Color(0x1FFFFFFF),
  ];

  test('paints every bundled icon in the colours its compiled SVG has', () {
    final catalog = _catalog();
    expect(catalog.length, greaterThan(100));
    for (final icon in catalog) {
      for (final tint in tints) {
        final glyph = TintableGlyph.of(
          icon.svg,
          tint.toARGB32() >>> 24,
          () => icon.tintableSvg,
        );
        expect(glyph, isNotNull, reason: '${icon.name} needs a picture');
        expect(
          glyph!.debugColors(tint),
          _compiledColors(icon, tint),
          reason: '${icon.name} tinted $tint',
        );
      }
    }
  });

  test('a new tint of the same opacity reuses the parsed glyph', () {
    TintableGlyph? glyph(Color tint) => TintableGlyph.of(
      DIcons.gear.svg,
      tint.toARGB32() >>> 24,
      () => DIcons.gear.tintableSvg,
    );

    expect(
      glyph(const Color(0xFF112233)),
      same(glyph(const Color(0xFF445566))),
    );
    expect(
      glyph(const Color(0x80112233)),
      isNot(same(glyph(const Color(0xFF112233)))),
    );
  });

  test('declines SVGs that need more than tinted fills and strokes', () {
    const gradient =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<defs><linearGradient id="g"><stop offset="0" stop-color="red"/>'
        '<stop offset="1" stop-color="blue"/></linearGradient></defs>'
        '<rect width="10" height="10" fill="url(#g)"/></svg>';
    const malformed = '<svg viewBox="0 0 10 10"><path d="M0 0L';

    for (final svg in [gradient, malformed]) {
      expect(TintableGlyph.of(svg, 255, () => svg), isNull, reason: svg);
    }
  });

  testWidgets('a palette change repaints the icon without a new glyph', (
    tester,
  ) async {
    Future<TintedIconGlyph> pump(Color color) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: DIcon(DIcons.gear, size: 24, color: color)),
        ),
      );
      return tester.widget<TintedIconGlyph>(find.byType(TintedIconGlyph));
    }

    final before = await pump(const Color(0xFF112233));
    final size = tester.getSize(find.byType(TintedIconGlyph));
    final after = await pump(const Color(0xFF998877));

    expect(after.glyph, same(before.glyph));
    expect(after.color, const Color(0xFF998877));
    expect(tester.getSize(find.byType(TintedIconGlyph)), size);
  });
}
