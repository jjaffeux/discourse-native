import 'dart:ui' show PointerDeviceKind;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final glass in [false, true]) {
      testWidgets(
        'split view keeps neutral artwork and only hovers in glass (dark: $dark, glass: $glass)',
        (tester) async {
          final strategy = FocusManager.instance.highlightStrategy;
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTouch;
          addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
          final focus = FocusNode();
          addTearDown(focus.dispose);
          var activations = 0;
          final theme = DMaterialTheme.apply(
            dark ? AppTheme.dark : AppTheme.light,
            glass
                ? DAppearanceMaterial.liquidGlass
                : DAppearanceMaterial.standard,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: DToggle.iconOnly(
                    density: DToggleDensity.splitView,
                    semanticLabel: 'Hide split view',
                    pressed: true,
                    focusNode: focus,
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
          final toggle = find.byType(DToggle);
          final bounds = tester.getRect(toggle);
          final art = find.descendant(
            of: toggle,
            matching: find.byType(AnimatedContainer),
          );
          BoxDecoration decoration() =>
              tester.widget<AnimatedContainer>(art).decoration!
                  as BoxDecoration;
          final tokens = DTokens.of(tester.element(toggle));
          final neutral = Color.lerp(
            tokens.colors.surface,
            tokens.foreground,
            .62,
          );
          Color? ink() =>
              IconTheme.of(tester.element(find.byType(DLayoutGlyph))).color;
          expect(bounds.size, const Size.square(36));
          expect(tester.getSize(find.byType(DLayoutGlyph)), const Size(20, 15));
          expect(ink(), neutral);
          expect(decoration().color, Colors.transparent);
          expect(decoration().borderRadius, BorderRadius.circular(999));
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(bounds.center);
          await tester.pumpAndSettle();
          expect(ink(), neutral);
          expect(decoration().color!.a, glass ? .28 : 0);
          expect(
            (decoration().border! as Border).top.color.a,
            glass ? (dark ? .14 : .75) : 0,
          );
          expect(tester.getRect(toggle), bounds);
          expect(
            tester.widget<DLayoutGlyph>(find.byType(DLayoutGlyph)).mainVisible,
            isFalse,
          );
          await mouse.down(bounds.center);
          await tester.pumpAndSettle();
          final hit = find.descendant(
            of: toggle,
            matching: find.byType(GestureDetector),
          );
          expect(tester.getRect(hit).width, moreOrLessEquals(36 * .92));
          expect(tester.getRect(hit), tester.getRect(art));
          await mouse.up();
          await mouse.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          expect(activations, 1);
          expect(decoration().color, Colors.transparent);
          expect(ink(), neutral);
          expect(
            tester.widget<DLayoutGlyph>(find.byType(DLayoutGlyph)).mainVisible,
            isTrue,
          );
          await tester.tapAt(bounds.topLeft - const Offset(1, 1));
          await tester.pumpAndSettle();
          expect(activations, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final reduced in [false, true]) {
    testWidgets('layout preview animates its panels (reduced: $reduced)', (
      tester,
    ) async {
      const boundaryKey = ValueKey('glyph-pixels');
      var secondary = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: IconTheme(
                      data: const IconThemeData(size: 20, color: Colors.white),
                      child: DLayoutGlyph(
                        mainVisible: true,
                        secondaryVisible: secondary,
                        changingPanel: 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      Future<List<int>> pixels() async {
        return (await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          final image = await boundary.toImage(pixelRatio: 4);
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes!.buffer.asUint8List();
        }))!;
      }

      final before = await pixels();
      rebuild(() => secondary = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midway = await pixels();
      await tester.pumpAndSettle();
      final after = await pixels();
      expect(after, isNot(orderedEquals(before)));
      expect(
        midway,
        reduced ? orderedEquals(after) : isNot(orderedEquals(after)),
      );
      if (!reduced) expect(midway, isNot(orderedEquals(before)));
    });
  }

  testWidgets(
    'layout preview follows hover and focus without changing bounds or value',
    (tester) async {
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
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
                density: DToggleDensity.splitView,
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
      expect(before.size, const Size.square(36));
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
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
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
              density: DToggleDensity.splitView,
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
