import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlass.precache);

  testWidgets('Native controls use full glass on the GPU renderer', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: DMaterialTheme.apply(
            AppTheme.forBrightness(brightness),
            DAppearanceMaterial.liquidGlass,
          ),
          home: Scaffold(
            body: Center(
              child: DButton(
                label: const Text('Glass action'),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlass), findsOneWidget);
      expect(find.byType(FakeGlass), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('dock keeps full overlapping glass in a small capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DMaterialTheme.apply(
          AppTheme.light,
          DAppearanceMaterial.liquidGlass,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 360,
              child: DMobileDock(
                onOverflowChanged: (_) {},
                destinations: [
                  DMobileDockItem(
                    icon: const Icon(Icons.home),
                    label: 'Home',
                    selected: true,
                    onPressed: () {},
                  ),
                  DMobileDockItem(
                    icon: const Icon(Icons.chat),
                    label: 'Chat',
                    onPressed: () {},
                  ),
                ],
                more: DMobileDockItem(
                  icon: const Icon(Icons.more_horiz),
                  label: 'More',
                  onPressed: () {},
                ),
                collapsedDestination: DMobileDockItem(
                  icon: const Icon(Icons.home),
                  label: 'Reveal',
                  collapsed: true,
                  onPressed: () {},
                ),
                action: DMobileDockAction(
                  icon: const Icon(Icons.add),
                  label: 'New topic',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FakeGlass), findsNothing);
    expect(find.byType(LiquidGlass), findsNWidgets(3));
    final capture = find.byType(LiquidGlassCapture);
    expect(capture, findsOneWidget);
    expect(tester.getSize(capture), const Size(360, 62));
    expect(tester.takeException(), isNull);
  });
}
