import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _preview => find.byType(DImagePreview);
Finder get _opacity =>
    find.descendant(of: _preview, matching: find.byType(AnimatedOpacity));

Future<void> _pump(
  WidgetTester tester, {
  double width = 400,
  double scale = 1,
  bool reduced = false,
  bool enabled = true,
  bool dark = false,
  TextDirection direction = TextDirection.ltr,
  TargetPlatform platform = TargetPlatform.macOS,
  VoidCallback? onPressed,
  Widget? child,
}) async {
  await tester.pumpWidget(
    DFocusHighlight(
      child: MaterialApp(
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: platform,
        ),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(scale),
            ),
            child: Directionality(
              textDirection: direction,
              child: Center(
                child: SizedBox(
                  width: width,
                  height: 150,
                  child: DImagePreview(
                    semanticLabel: 'Open image: landscape.png',
                    filename: 'landscape-with-a-very-long-filename.png',
                    details: '1024×512 128 KB',
                    onPressed: enabled ? onPressed ?? () {} : null,
                    child: child ?? const ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hover shadows stay outside transparent image pixels', (
    tester,
  ) async {
    final previous = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = previous);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: SizedBox(
                width: 200,
                height: 100,
                child: DImagePreview(
                  semanticLabel: 'Open transparent image',
                  onPressed: () {},
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(_preview));
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: 1),
    ))!;
    final pixels = (await tester.runAsync(() => image.toByteData()))!;
    debugDisableShadows = previous;
    int alpha(int x, int y) => pixels.getUint8((y * image.width + x) * 4 + 3);
    expect(
      alpha(100, 50),
      0,
      reason: 'The image interior must stay transparent.',
    );
    expect(
      alpha(28, 80),
      greaterThan(0),
      reason: 'The exterior must still cast a shadow.',
    );
    image.dispose();
    await mouse.removePointer();
  });

  testWidgets('hover fades metadata and shadow without resizing the image', (
    tester,
  ) async {
    await _pump(tester);
    final bounds = tester.getRect(_preview);
    expect(tester.widget<AnimatedOpacity>(_opacity).opacity, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(bounds.center);
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(_opacity).duration,
      const Duration(milliseconds: 500),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final fade = tester.widget<FadeTransition>(
      find.descendant(of: _opacity, matching: find.byType(FadeTransition)),
    );
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(.9));
    await tester.pumpAndSettle();
    expect(fade.opacity.value, .9);
    expect(tester.getRect(_preview), bounds);
    final decoration =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: _preview,
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(decoration.boxShadow!.every((s) => s.color.a > 0), isTrue);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(_opacity).duration,
      const Duration(milliseconds: 200),
    );
    await tester.pumpAndSettle();
    expect(fade.opacity.value, 0);
    await mouse.removePointer();
  });

  testWidgets(
    'keyboard focus reveals metadata and Enter and Space activate once',
    (tester) async {
      var opened = 0;
      await _pump(tester, onPressed: () => opened++);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(_opacity).opacity, .9);
      final surface = tester.widget<DecoratedBox>(
        find.descendant(
          of: _preview,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.position == DecorationPosition.foreground,
          ),
        ),
      );
      final ring = (surface.decoration as BoxDecoration).border! as Border;
      expect(ring.top.color.a, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(opened, 2);
    },
  );

  testWidgets(
    'metadata passes clicks to the image and preserves child controls',
    (tester) async {
      var opened = 0;
      var paused = 0;
      await _pump(
        tester,
        onPressed: () => opened++,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.blue)),
            PositionedDirectional(
              top: 4,
              end: 4,
              child: DButton(
                label: const Text('Pause GIF'),
                onPressed: () => paused++,
              ),
            ),
          ],
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_preview));
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getBottomLeft(_preview) + const Offset(30, -12),
      );
      expect(opened, 1);
      await tester.tap(find.text('Pause GIF'));
      expect(paused, 1);
      expect(opened, 1);
      await mouse.removePointer();
    },
  );

  testWidgets('touch has an expand hint and opens with one tap', (
    tester,
  ) async {
    var opened = 0;
    await _pump(
      tester,
      platform: TargetPlatform.iOS,
      onPressed: () => opened++,
    );
    expect(tester.widget<AnimatedOpacity>(_opacity).opacity, .8);
    expect(find.text('landscape-with-a-very-long-filename.png'), findsNothing);
    await tester.tap(_preview);
    expect(opened, 1);
  });

  testWidgets('disabled previews do not react to hover or activation', (
    tester,
  ) async {
    await _pump(tester, enabled: false);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(_preview));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(_opacity).opacity, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(_opacity).opacity, 0);
    await mouse.removePointer();
  });

  testWidgets('metadata stays supplementary to the named image action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(find.bySemanticsLabel('Open image: landscape.png'), findsOneWidget);
    expect(find.bySemanticsLabel('1024×512 128 KB'), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'narrow RTL and large text stay within the image in both palettes',
    (tester) async {
      for (final dark in [false, true]) {
        for (final width in [12.0, 90.0, 240.0, 400.0]) {
          await _pump(
            tester,
            width: width,
            scale: 2,
            dark: dark,
            direction: TextDirection.rtl,
            reduced: true,
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: tester.getCenter(_preview));
          await tester.pumpAndSettle();
          expect(
            tester.widget<AnimatedOpacity>(_opacity).duration,
            Duration.zero,
          );
          expect(tester.getSize(_preview), Size(width, 150));
          expect(tester.takeException(), isNull);
          await mouse.removePointer();
        }
      }
    },
  );
}
