import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/button_surface.dart';

void main() {
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('filter pill geometry and activation $platform at $scale', (
        tester,
      ) async {
        var activated = 0;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: DTouchTargets(
                child: Center(
                  child: DButton(
                    density: DButtonDensity.filterPill,
                    variant: DButtonVariant.tool,
                    focusNode: focus,
                    icon: const DAvatar(dimension: 18, border: false),
                    label: const Text('Design'),
                    onPressed: () => activated++,
                  ),
                ),
              ),
            ),
          ),
        );
        final button = find.byType(FilledButton);
        final rect = tester.getRect(button);
        expect(rect.height, closeTo(30 + 12.5 * (scale - 1) * 1.5, .01));
        final text = find.text('Design');
        expect(tester.getTopLeft(find.byType(DAvatar)).dx - rect.left, 9);
        expect(rect.right - tester.getTopRight(text).dx, closeTo(9, .01));
        expect(tester.getSize(find.byType(DAvatar)), const Size(18, 18));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.text.style!.fontSize, 12.5);
        expect(paragraph.text.style!.fontWeight, FontWeight.w400);
        expect(buttonSurface(tester).borderRadius.topLeft.x, DRadius.pill);
        await tester.tap(button);
        expect(activated, 1);
        focus.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(activated, 2);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
