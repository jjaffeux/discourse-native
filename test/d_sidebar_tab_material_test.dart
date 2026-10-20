import 'dart:ui' show ImageByteFormat;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'support/stock_glass.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'sidebar glass uses button lighting for selection and hover ($dark)',
      (tester) async {
        for (final backdrop in [
          const Color(0xff555555),
          const Color(0xffaaaaaa),
        ]) {
          await _mount(tester, dark: dark, backdrop: backdrop);
          final tokens = DTokens.of(
            tester.element(find.byKey(const ValueKey('forum'))),
          );

          final well = Color.alphaBlend(
            Colors.black.withValues(alpha: dark ? .16 : .045),
            backdrop,
          );
          final selected = find.descendant(
            of: find.byKey(const ValueKey('forum')),
            matching: find.byType(LiquidGlassLens),
          );
          expectStockGlass(
            tester.widget<LiquidGlassLens>(selected).style,
            expectedButtonGlassStyle,
          );
          await _pixel(tester, const Offset(340, 25), well);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(700, 500));
          await mouse.moveTo(
            tester.getCenter(find.byKey(const ValueKey('chat'))),
          );
          await tester.pumpAndSettle();
          expect(
            IconTheme.of(tester.element(find.byIcon(Icons.chat))).color,
            tokens.mutedForeground,
          );
          final hovered = find.descendant(
            of: find.byKey(const ValueKey('chat')),
            matching: find.byType(LiquidGlassLens),
          );
          expectStockGlass(
            tester.widget<LiquidGlassLens>(hovered).style,
            expectedButtonGlassStyle,
          );
          await mouse.removePointer();
          await tester.pumpAndSettle();
          await _pixel(tester, const Offset(340, 25), well);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('high contrast retains an opaque selected sidebar capsule', (
    tester,
  ) async {
    await _mount(
      tester,
      dark: true,
      backdrop: const Color(0xff49405f),
      highContrast: true,
    );
    final tokens = DTokens.of(
      tester.element(find.byKey(const ValueKey('forum'))),
    );
    await _pixel(
      tester,
      const Offset(250, 25),
      Color.lerp(tokens.background, tokens.foreground, .03)!,
    );
  });
}

Future<void> _mount(
  WidgetTester tester, {
  required bool dark,
  required Color backdrop,
  bool highContrast = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: DMaterialTheme.apply(
        dark ? AppTheme.dark : AppTheme.light,
        DAppearanceMaterial.liquidGlass,
      ),
      home: MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: const ValueKey('paint'),
            child: ColoredBox(
              color: backdrop,
              child: SizedBox(
                width: 400,
                child: DTabs<String>.controlled(
                  value: 'forum',
                  onChanged: (_) {},
                  children: const [
                    DTabList<String>(
                      expandSelected: true,
                      children: [
                        DTabTrigger(
                          key: ValueKey('forum'),
                          value: 'forum',
                          selectedLabelOnly: true,
                          semanticLabel: 'Forum',
                          icon: Icon(Icons.layers),
                          child: Text('Forum'),
                        ),
                        DTabTrigger(
                          key: ValueKey('chat'),
                          value: 'chat',
                          selectedLabelOnly: true,
                          semanticLabel: 'Chat',
                          icon: Icon(Icons.chat),
                          child: Text('Chat'),
                        ),
                        DTabTrigger(
                          value: 'shortcuts',
                          selectedLabelOnly: true,
                          semanticLabel: 'Shortcuts',
                          icon: Icon(Icons.bolt),
                          child: Text('Shortcuts'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pixel(WidgetTester tester, Offset point, Color expected) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('paint')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      final offset = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
      for (final (i, channel) in [expected.r, expected.g, expected.b].indexed) {
        expect(bytes.getUint8(offset + i), closeTo(channel * 255, 3));
      }
    } finally {
      image.dispose();
    }
  });
}
