import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'layout preview follows hover and focus without changing bounds or value',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: DToggle.iconOnly(
                key: const ValueKey('layout-toggle'),
                focusNode: focus,
                semanticLabel: 'Hide split view',
                density: DToggleDensity.chrome,
                variant: DToggleVariant.inline,
                pressed: true,
                onPressedChanged: (_) => activations++,
                icon: const DLayoutGlyph(
                  mainVisible: true,
                  secondaryVisible: true,
                  changingPanel: 0,
                ),
                interactiveIcon: const DLayoutGlyph(
                  mainVisible: false,
                  secondaryVisible: true,
                  changingPanel: 0,
                ),
              ),
            ),
          ),
        ),
      );
      final toggle = find.byKey(const ValueKey('layout-toggle'));
      final before = tester.getRect(toggle);
      expect(before.size, const Size.square(32));
      expect(
        tester.widget<DLayoutGlyph>(find.byType(DLayoutGlyph)).mainVisible,
        isTrue,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(before.center);
      await tester.pump();
      expect(
        tester.widget<DLayoutGlyph>(find.byType(DLayoutGlyph)).mainVisible,
        isFalse,
      );
      expect(tester.getRect(toggle), before);
      expect(activations, 0);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(
        tester.widget<DLayoutGlyph>(find.byType(DLayoutGlyph)).mainVisible,
        isTrue,
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(
        tester.widget<DLayoutGlyph>(find.byType(DLayoutGlyph)).mainVisible,
        isFalse,
      );
      await tester.tap(toggle);
      await tester.pump();
      expect(activations, 1);
      expect(tester.getRect(toggle), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled toggle keeps current glyph under the pointer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: DToggle.iconOnly(
              semanticLabel: 'Split view',
              enabled: false,
              icon: DLayoutGlyph(
                mainVisible: true,
                secondaryVisible: true,
                changingPanel: 1,
              ),
              interactiveIcon: DLayoutGlyph(
                mainVisible: true,
                secondaryVisible: false,
                changingPanel: 1,
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(DToggle)));
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(
      tester.widget<DLayoutGlyph>(find.byType(DLayoutGlyph)).secondaryVisible,
      isTrue,
    );
  });
}
