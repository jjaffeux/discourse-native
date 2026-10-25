import 'dart:ui' show ImageByteFormat;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  for (final dark in [false, true]) {
    {
      testWidgets('tab tint follows the backdrop ($dark, flat)', (
        tester,
      ) async {
        final theme = dark ? AppTheme.dark : AppTheme.light;
        for (final backdrop in [
          const Color(0xff333333),
          const Color(0xffaaaaaa),
        ]) {
          await _pump(tester, theme: theme, backdrop: backdrop);
          final tokens = DTokens.of(tester.element(find.byType(DDocumentTab)));
          final raised = Color.lerp(tokens.background, tokens.foreground, .1)!;
          await _expectPixel(tester, const Offset(120, 25), raised);

          final surface = tester.widget<Container>(
            find.byKey(const ValueKey('surface')),
          );
          final decoration = surface.decoration! as ShapeDecoration;
          expect(
            (decoration.shape as OutlinedBorder).side.color,
            Color.lerp(tokens.background, tokens.foreground, .22),
          );
          final tab = tester.getRect(find.byType(DDocumentTab));
          final close = tester.getRect(find.byKey(const ValueKey('close')));
          expect(tab.right - close.right, 11);
          expect(close.size, const Size.square(18));
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets(
        'inactive hover and close keep reference paint ($dark, flat)',
        (tester) async {
          const backdrop = Color(0xff555555);
          await _pump(
            tester,
            theme: dark ? AppTheme.dark : AppTheme.light,
            backdrop: backdrop,
            selected: false,
          );
          await _expectPixel(tester, const Offset(120, 25), backdrop);
          final tab = find.byType(DDocumentTab);
          final rect = tester.getRect(tab);
          final tokens = DTokens.of(tester.element(tab));
          final pointer = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await pointer.addPointer(location: Offset.zero);
          addTearDown(pointer.removePointer);
          await pointer.moveTo(tester.getCenter(tab));
          await tester.pumpAndSettle();

          await _expectPixel(tester, const Offset(120, 25), backdrop);
          final surface = tester.widget<Container>(
            find.byKey(const ValueKey('surface')),
          );
          expect(
            ((surface.decoration! as ShapeDecoration).shape as OutlinedBorder)
                .side
                .color,
            Colors.transparent,
          );

          expect(tester.getRect(tab), rect);
          final close = find.byKey(const ValueKey('close'));
          await pointer.moveTo(tester.getCenter(close));
          await tester.pumpAndSettle();
          expect(buttonSurface(tester, of: close).color, Colors.transparent);
          expect(
            tester.widget<DButton>(close).foregroundColor,
            Color.lerp(tokens.background, tokens.foreground, .5),
          );
          await pointer.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          await _expectPixel(tester, const Offset(120, 25), backdrop);
        },
      );
    }
  }

  testWidgets('high contrast uses the opaque standard selection', (
    tester,
  ) async {
    await _pump(tester, theme: AppTheme.dark, highContrast: true);
    final tokens = DTokens.of(tester.element(find.byType(DDocumentTab)));
    await _expectPixel(
      tester,
      const Offset(120, 25),
      Color.lerp(tokens.background, tokens.foreground, .1)!,
    );
  });

  testWidgets(
    'touch exposes the inactive close action inside its visible bounds',
    (tester) async {
      await _pump(
        tester,
        theme: AppTheme.dark.copyWith(platform: TargetPlatform.iOS),
        selected: false,
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('close'))),
        const Size.square(18),
      );
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  Color backdrop = const Color(0xff555555),
  bool selected = true,
  bool highContrast = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationStyle: AnimationStyle.noAnimation,
      home: DFocusHighlight(
        child: MediaQuery(
          data: MediaQueryData(highContrast: highContrast),
          child: Center(
            child: RepaintBoundary(
              key: const ValueKey('paint'),
              child: ColoredBox(
                color: backdrop,
                child: SizedBox(
                  width: 240,
                  child: DDocumentTab(
                    size: DControlSize.documentTab,
                    selected: selected,
                    surfaceKey: const ValueKey('surface'),
                    closeKey: const ValueKey('close'),
                    onSelect: () {},
                    onClose: () {},
                    closeLabel: 'Close Review',
                    child: const Text('Review'),
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
}

Future<void> _expectPixel(
  WidgetTester tester,
  Offset point,
  Color expected,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('paint')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      final offset = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
      final channels = [expected.r, expected.g, expected.b];
      for (var i = 0; i < 3; i++) {
        expect(bytes.getUint8(offset + i), closeTo(channels[i] * 255, 2));
      }
    } finally {
      image.dispose();
    }
  });
}
