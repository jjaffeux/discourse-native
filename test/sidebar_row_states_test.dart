import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _paint = ValueKey('sidebar-state-paint');
const _selected = ValueKey('selected-link');
const _other = ValueKey('other-link');
const _backdrop = Color(0xff686078);

void main() {
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final kind in ['menu', 'navigation', 'conversation']) {
    for (final dark in [false, true]) {
      testWidgets('sidebar $kind hover and selection: $dark', (tester) async {
        final semantics = tester.ensureSemantics();
        var selected = true;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(),
              child: Align(
                alignment: Alignment.topLeft,
                child: RepaintBoundary(
                  key: _paint,
                  child: ColoredBox(
                    color: _backdrop,
                    child: SizedBox(
                      width: 320,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: StatefulBuilder(
                          builder: (context, setState) {
                            rebuild = setState;
                            Widget row(
                              Key key,
                              String label, {
                              required bool active,
                            }) => kind == 'conversation'
                                ? DItem(
                                    key: key,
                                    shape: DItemShape.menu,
                                    selectionStyle: DItemSelectionStyle.sidebar,
                                    selected: active,
                                    showSelectionIndicator: false,
                                    onPressed: () {},
                                    children: [
                                      DItemContent(
                                        children: [
                                          DItemTitle(child: Text(label)),
                                          const DItemDescription(
                                            child: Text('Last message'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : DSidebarMenuButton(
                                    key: key,
                                    variant: kind == 'navigation'
                                        ? DSidebarMenuButtonVariant.navigation
                                        : DSidebarMenuButtonVariant.menu,
                                    isActive: active,
                                    onPressed: () {},
                                    child: Text(label),
                                  );
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                row(_selected, 'General', active: selected),
                                const SizedBox(height: 8),
                                row(_other, 'Other channel', active: false),
                              ],
                            );
                          },
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
        final tokens = DTokens.of(tester.element(find.byKey(_selected)));
        final tint = kind == 'navigation'
            ? Color.lerp(tokens.background, tokens.foreground, .12)!
            : tokens.foreground.withValues(alpha: .13);
        final selectedPixel = await _sample(tester, _selected);
        final upperPixel = await _sample(
          tester,
          _selected,
          fraction: const Offset(.7, .15),
        );
        await _capture(tester, 'sidebar-$kind-$dark-selected');

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(700, 500));
        await mouse.moveTo(tester.getCenter(find.byKey(_other)));
        await tester.pumpAndSettle();
        await _capture(tester, 'sidebar-$kind-$dark-hover');
        final hoverPixel = await _sample(tester, _other);
        final activeUnderHover = await _sample(tester, _selected);
        expect(
          tester
              .getSemantics(find.byKey(_selected))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          ui.Tristate.isTrue,
        );
        expect(
          tester
              .getSemantics(find.byKey(_other))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          isNot(ui.Tristate.isTrue),
        );
        semantics.dispose();
        await mouse.removePointer();
        await tester.pumpAndSettle();
        final restingPixel = await _sample(tester, _other);
        rebuild(() => selected = false);
        await tester.pumpAndSettle();
        final clearedPixel = await _sample(tester, _selected);

        _expectColor(selectedPixel, Color.alphaBlend(tint, _backdrop));
        _expectColor(upperPixel, Color.alphaBlend(tint, _backdrop));
        _expectColor(activeUnderHover, selectedPixel);
        _expectColor(
          hoverPixel,
          kind == 'navigation'
              ? _backdrop
              : Color.alphaBlend(
                  tokens.foreground.withValues(alpha: .08),
                  _backdrop,
                ),
        );
        _expectColor(restingPixel, _backdrop);
        _expectColor(clearedPixel, _backdrop);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<Color> _sample(WidgetTester tester, Key key, {Offset? fraction}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_paint),
  );
  final rect = tester
      .getRect(find.byKey(key))
      .shift(-tester.getTopLeft(find.byKey(_paint)));
  final point = fraction == null
      ? Offset(rect.right - 20, rect.bottom - 8)
      : rect.topLeft +
            Offset(rect.width * fraction.dx, rect.height * fraction.dy);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
    final color = Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
    image.dispose();
    return color;
  }))!;
}

void _expectColor(Color actual, Color expected) {
  for (final pair in [
    (actual.r, expected.r),
    (actual.g, expected.g),
    (actual.b, expected.b),
  ]) {
    expect(pair.$1 * 255, closeTo(pair.$2 * 255, 3));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SIDEBAR_STATES_REVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_paint),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
