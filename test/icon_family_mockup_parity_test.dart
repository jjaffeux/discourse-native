import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/composer/components/image.dart';
import 'package:discourse_native/src/shell/composer/components/image_source.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/selection_menu.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon_glyph.dart';
import 'package:discourse_native/src/theme/d_icon_sets.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_native_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = ValueKey('icon-family-capture');

void main() {
  setUpAll(() async {
    await (FontLoader('Lato')
          ..addFont(rootBundle.load('assets/fonts/Lato-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Lato-Bold.ttf')))
        .load();
  });
  for (final family in DIconSet.values) {
    for (final width in [390.0, 900.0]) {
      testWidgets('${family.name} glyphs and actions at $width', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.reset);
        final composer = ComposerController(
          const ReplyComposerTarget(
            privateMessageTopic: false,
            siteUrl: 'https://example.test',
            topicId: 1,
            slug: 'topic',
            topicTitle: 'Topic',
          ),
        );
        addTearDown(composer.dispose);
        composer.text.value = const TextEditingValue(
          text: 'sample text',
          selection: TextSelection(baseOffset: 0, extentOffset: 6),
        );
        final alt = TextEditingController(text: 'A boat');
        addTearDown(alt.dispose);
        final scales = <int>[];
        var saved = false;
        var deleted = false;
        var selected = true;
        await tester.pumpWidget(
          RepaintBoundary(
            key: _capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.fromPalette(
                forumThemePresets
                    .firstWhere((preset) => preset.id == 'dracula')
                    .resolve(Brightness.dark),
                fontFamily: 'Lato',
              ).copyWith(platform: TargetPlatform.macOS),
              home: DIconSetScope(
                iconSet: family,
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 350,
                      child: StatefulBuilder(
                        builder: (context, setState) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 24,
                          children: [
                            Text(family.label),
                            Row(
                              children: [
                                DCheckbox(
                                  key: const ValueKey('checked'),
                                  value: selected,
                                  onChanged: (value) =>
                                      setState(() => selected = value == true),
                                ),
                                DCheckbox(
                                  key: const ValueKey('mixed'),
                                  value: null,
                                  tristate: true,
                                  onChanged: (_) {},
                                ),
                              ],
                            ),
                            ComposerFormattingControls(
                              composer: composer,
                              onLink: () {},
                            ),
                            ComposerImageMenu(
                              image: const ComposerImageBlock(
                                start: 0,
                                end: 1,
                                source: 'x',
                                alt: 'A boat',
                                url: 'https://example.test/boat.png',
                                scale: 75,
                              ),
                              gallery: null,
                              alt: alt,
                              onSaveAlt: () => saved = true,
                              onDelete: () => deleted = true,
                              onScale: scales.add,
                            ),
                            DDropdownMenu(
                              content: DDropdownMenuContent(
                                children: [
                                  DDropdownMenuCheckboxItem(
                                    key: const ValueKey('menu-checked'),
                                    checked: selected,
                                    onChanged: (value) =>
                                        setState(() => selected = value),
                                    child: const Text('Show section'),
                                  ),
                                  DDropdownMenuRadioGroup(
                                    value: 'all',
                                    onChanged: (_) {},
                                    children: const [
                                      DDropdownMenuRadioItem(
                                        value: 'all',
                                        child: Text('All'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              child: DDropdownMenuTrigger.button(
                                label: const Text('Options'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final icon in [
          DIcons.bold,
          DIcons.italic,
          DIcons.link,
          DNativeIcons.underline,
          DNativeIcons.eraser,
          DNativeIcons.strikethrough,
          DIcons.code,
          DIcons.minus,
          DIcons.plus,
          DIcons.trashCan,
        ]) {
          expect(
            find.byWidgetPredicate(
              (widget) => widget is DIcon && widget.icon == icon,
            ),
            findsWidgets,
          );
          if (family != DIconSet.defaultSet) {
            expect(
              alternateIconSvg(family, icon.name),
              isNotNull,
              reason: icon.name,
            );
          }
        }
        final checked = find.byKey(const ValueKey('checked'));
        final glyph = find.descendant(
          of: checked,
          matching: find.byType(TintedIconGlyph),
        );
        expect(glyph, findsOneWidget);
        final expectedViewBox = switch (family) {
          DIconSet.defaultSet => const Size(448, 512),
          DIconSet.phosphor => const Size.square(256),
          DIconSet.lucide || DIconSet.tabler => const Size.square(24),
        };
        expect(
          tester.widget<TintedIconGlyph>(glyph).glyph.size,
          expectedViewBox,
        );
        expect(find.byType(Icon), findsNothing);
        await _saveCapture(tester, '${family.name}-${width.toInt()}-controls');
        await tester.tap(find.byTooltip('Decrease image size'));
        await tester.tap(find.byTooltip('Increase image size'));
        expect(scales, [50, 100]);
        await tester.tap(find.byTooltip('Save alt text'));
        await tester.tap(find.byTooltip('Delete image'));
        expect(saved, isTrue);
        expect(deleted, isTrue);
        await tester.tap(find.text('Options'));
        await tester.pumpAndSettle();
        final menu = find.byKey(const ValueKey('menu-checked'));
        final menuGlyph = find.descendant(
          of: menu,
          matching: find.byType(TintedIconGlyph),
        );
        expect(menuGlyph, findsOneWidget);
        expect(
          tester.widget<TintedIconGlyph>(menuGlyph).glyph.size,
          expectedViewBox,
        );
        await _saveCapture(tester, '${family.name}-${width.toInt()}-menu');
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(tester.widget<DDropdownMenuCheckboxItem>(menu).checked, isFalse);
        expect(
          find.descendant(of: checked, matching: find.byType(DIcon)),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _saveCapture(WidgetTester tester, String name) async {
  final path = Platform.environment['ICON_FAMILY_CAPTURE_DIR'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(path).create(recursive: true);
      await File('$path/$name.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
