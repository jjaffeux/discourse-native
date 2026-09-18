import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  testWidgets('mockup families repaint on live palette changes and activate', (
    tester,
  ) async {
    var presses = 0;
    for (final dark in [true, false, true]) {
      // The reference's Dracula palette and a light forum palette.
      final canvas = dark ? const Color(0xff282a36) : Colors.white;
      final ink = dark ? const Color(0xfff8f8f2) : const Color(0xff222222);
      final accent = dark ? const Color(0xffbd93f9) : const Color(0xff0088cc);
      final colors = ColorScheme.fromSeed(
        seedColor: accent,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(primary: accent, onSurface: ink);
      final base = ThemeData(
        colorScheme: colors,
        platform: TargetPlatform.macOS,
      );
      final tokens = DTokens.fromTheme(base).copyWith(background: canvas);
      await tester.pumpWidget(
        MaterialApp(
          theme: base.copyWith(extensions: [tokens]),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Wrap(
              children: [
                for (final variant in [
                  DButtonVariant.primary,
                  DButtonVariant.outline,
                  DButtonVariant.transparentBackground,
                ])
                  DButton(
                    key: ValueKey(variant),
                    label: Text(variant.name),
                    variant: variant,
                    onPressed: () => presses++,
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final primary = find.byKey(const ValueKey(DButtonVariant.primary));
      final outline = find.byKey(const ValueKey(DButtonVariant.outline));
      final clear = find.byKey(
        const ValueKey(DButtonVariant.transparentBackground),
      );
      expect(
        buttonSurface(tester, of: primary).color,
        Color.lerp(canvas, accent, .25),
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('primary'))).style.color,
        Color.lerp(ink, accent, .5),
      );
      expect(
        buttonSurface(tester, of: outline).borderColor,
        Color.lerp(canvas, ink, .22),
      );
      expect(buttonSurface(tester, of: outline).strokeWidth, 1);
      expect(buttonSurface(tester, of: clear).color.a, 0);
      expect(buttonSurface(tester, of: clear).borderColor.a, 0);
      for (final button in [primary, outline, clear]) {
        expect(buttonSurface(tester, of: button).shadowColor.a, 0);
        expect(
          buttonSurface(tester, of: button).borderRadius,
          BorderRadius.circular(8),
        );
        await tester.tap(button);
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(clear));
      await tester.pump();
      expect(
        buttonSurface(tester, of: clear).color,
        ink.withValues(alpha: .08),
      );
      await mouse.removePointer();
    }
    expect(presses, 9);
  });
}
