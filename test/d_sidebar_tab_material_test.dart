import 'dart:ui' show ImageByteFormat;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the chosen side and the well take the reference fills', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final backdrop = dark ? const Color(0xff49405f) : const Color(0xffe8e4ef);
      await _mount(tester, dark: dark, backdrop: backdrop);
      final tokens = DTokens.of(
        tester.element(find.byKey(const ValueKey('forum'))),
      );
      await _pixel(
        tester,
        const Offset(250, 25),
        dark
            ? Color.lerp(tokens.background, tokens.foreground, .18)!
            : tokens.background,
      );
      // The well's edge, one pixel in from the strip's top.
      await _pixel(
        tester,
        const Offset(250, 0),
        Color.lerp(tokens.background, tokens.foreground, .12)!,
      );
    }
  });

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
      Color.lerp(tokens.background, tokens.foreground, .18)!,
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
      theme: dark ? AppTheme.dark : AppTheme.light,
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
