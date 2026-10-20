import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

Future<void> _mount(WidgetTester tester, Widget child, ThemeData theme) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationStyle: AnimationStyle.noAnimation,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectLiveLens(WidgetTester tester) {
  final lens = find.byType(LiquidGlassLens);
  expect(lens, findsOneWidget);
  RenderObject? ancestor = tester.renderObject(lens).parent;
  while (ancestor != null) {
    final opacity = switch (ancestor) {
      RenderOpacity(:final opacity) => opacity,
      RenderAnimatedOpacity(:final opacity) => opacity.value,
      _ => 1.0,
    };
    expect(
      opacity,
      1,
      reason: 'Stock glass must sample the page while its content dims.',
    );
    ancestor = ancestor.parent;
  }
}

void main() {
  testWidgets('stock glass preserves explicit and destructive button colors', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final theme = dark ? AppTheme.dark : AppTheme.light;
      for (final variant in [
        DButtonVariant.outline,
        DButtonVariant.destructive,
      ]) {
        final button = DButton(
          variant: variant,
          foregroundColor: variant == DButtonVariant.outline
              ? Colors.orange
              : null,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Action'),
          onPressed: () {},
        );
        await _mount(
          tester,
          button,
          DMaterialTheme.apply(theme, DAppearanceMaterial.standard),
        );
        final expectedText = DefaultTextStyle.of(
          tester.element(find.text('Action')),
        ).style.color;
        final expectedIcon = IconTheme.of(
          tester.element(find.byIcon(Icons.delete_outline)),
        ).color;
        await _mount(
          tester,
          button,
          DMaterialTheme.apply(theme, DAppearanceMaterial.liquidGlass),
        );
        expect(find.byType(LiquidGlassLens), findsOneWidget);
        expect(
          DefaultTextStyle.of(tester.element(find.text('Action'))).style.color,
          expectedText,
        );
        expect(
          IconTheme.of(tester.element(find.byIcon(Icons.delete_outline))).color,
          expectedIcon,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'disabled filters keep live glass and inactive split toggles stay flat',
    (tester) async {
      for (final dark in [false, true]) {
        for (final density in [
          DToggleDensity.menuFilter,
          DToggleDensity.splitView,
        ]) {
          await _mount(
            tester,
            DToggle(
              density: density,
              pressed: true,
              enabled: false,
              child: const Text('Selected'),
            ),
            DMaterialTheme.apply(
              dark ? AppTheme.dark : AppTheme.light,
              DAppearanceMaterial.liquidGlass,
            ),
          );
          if (density == DToggleDensity.menuFilter) {
            _expectLiveLens(tester);
          } else {
            expect(find.byType(LiquidGlassLens), findsNothing);
          }
          expect(
            find.byWidgetPredicate(
              (widget) => widget is Opacity && widget.opacity == .6,
            ),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('disabled selected expanding tab keeps live glass', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await _mount(
        tester,
        const SizedBox(
          width: 240,
          child: DTabs<String>.controlled(
            value: 'forum',
            enabled: false,
            children: [
              DTabList<String>(
                expandSelected: true,
                children: [
                  DTabTrigger<String>(
                    value: 'forum',
                    icon: Icon(Icons.forum),
                    child: Text('Forum'),
                  ),
                  DTabTrigger<String>(
                    value: 'chat',
                    icon: Icon(Icons.chat),
                    child: Text('Chat'),
                  ),
                ],
              ),
            ],
          ),
        ),
        DMaterialTheme.apply(
          dark ? AppTheme.dark : AppTheme.light,
          DAppearanceMaterial.liquidGlass,
        ),
      );
      _expectLiveLens(tester);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Opacity && widget.opacity == .5,
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
