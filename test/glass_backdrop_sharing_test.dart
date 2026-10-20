import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

Widget _fixture(Widget child) => MaterialApp(
  theme: DMaterialTheme.apply(AppTheme.light, DAppearanceMaterial.liquidGlass),
  home: Center(child: child),
);

void main() {
  testWidgets('sibling controls share one stable backdrop sample', (
    tester,
  ) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      _fixture(
        ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, value, _) => DMaterialBatch(
            enabled: value,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DButton(label: const Text('First'), onPressed: () {}),
                DButton(label: const Text('Second'), onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    List<BackdropKey?> samples() => tester
        .widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
        .map((layer) => layer.backdropKey)
        .toList();
    final initial = samples();
    expect(initial, hasLength(2));
    expect(initial.first, isNotNull);
    expect(initial.last, same(initial.first));
    enabled.value = false;
    await tester.pumpAndSettle();
    expect(samples(), everyElement(isNull));
    enabled.value = true;
    await tester.pumpAndSettle();
    expect(samples(), everyElement(same(initial.first)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel captures stay bounded to individual controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _fixture(
        SizedBox(
          width: 300,
          height: 150,
          child: DMaterialSurface(
            depth: DSurfaceDepth.panel,
            color: Colors.white,
            radius: BorderRadius.circular(20),
            child: DMaterialBatch(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DButton(label: const Text('First'), onPressed: () {}),
                    DButton(label: const Text('Second'), onPressed: () {}),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final captures = find.byType(LiquidGlassCapture);
    expect(captures, findsNWidgets(2));
    for (final element in captures.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.width, lessThan(300));
      expect(size.height, lessThan(150));
    }
    expect(
      tester
          .widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .map((layer) => layer.backdropKey),
      everyElement(isNull),
    );
    expect(tester.takeException(), isNull);
  });

  for (final depth in [
    DSurfaceDepth.menu,
    DSurfaceDepth.dialog,
    DSurfaceDepth.sheet,
  ]) {
    testWidgets('$depth samples its own painted content above a batch', (
      tester,
    ) async {
      await tester.pumpWidget(
        _fixture(
          DMaterialBatch(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DButton(label: const Text('Parent'), onPressed: () {}),
                DMaterialSurface(
                  depth: depth,
                  color: Colors.white,
                  radius: BorderRadius.circular(12),
                  child: DButton(
                    label: const Text('Overlay'),
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layers = tester.widgetList<LiquidGlassLayer>(
        find.byType(LiquidGlassLayer),
      );
      expect(layers, hasLength(3));
      expect(layers.first.backdropKey, isNotNull);
      expect(
        layers.skip(1).map((layer) => layer.backdropKey),
        everyElement(isNull),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
