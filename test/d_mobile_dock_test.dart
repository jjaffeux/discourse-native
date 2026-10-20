import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/material_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'support/stock_glass.dart' show expectedButtonGlassStyle;

Widget fixture({
  double width = 390,
  bool collapsed = false,
  bool withAction = true,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
  ValueChanged<int>? onOverflow,
  VoidCallback? onReveal,
  bool hidden = false,
  ThemeData? theme,
  Color backdrop = Colors.white,
  bool highContrast = false,
  bool reducedMotion = false,
}) => MaterialApp(
  theme: theme,
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(scale),
      highContrast: highContrast,
      disableAnimations: reducedMotion,
    ),
    child: Directionality(
      textDirection: direction,
      child: RepaintBoundary(
        key: const ValueKey('dock-capture'),
        child: Scaffold(
          backgroundColor: backdrop,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: DMobileDock(
                  collapsed: collapsed,
                  destinationsHidden: hidden,
                  onOverflowChanged: onOverflow ?? (_) {},
                  destinations: [
                    for (final name in [
                      'Start',
                      'Topics',
                      'Chat',
                      'Inbox',
                      'Users',
                      'A very long destination',
                    ])
                      DMobileDockItem(
                        key: ValueKey(name),
                        icon: const Icon(Icons.forum),
                        label: name,
                        badge: name == 'Chat'
                            ? const DBadge.overlay(child: Text('99+'))
                            : null,
                        selected: name == 'Topics',
                        onPressed: () {},
                      ),
                  ],
                  more: DMobileDockItem(
                    key: const ValueKey('more'),
                    bare: true,
                    icon: const Icon(Icons.more_vert),
                    label: 'More',
                    onPressed: () {},
                  ),
                  collapsedDestination: DMobileDockItem(
                    key: const ValueKey('reveal'),
                    collapsed: true,
                    icon: const Icon(Icons.forum),
                    label: 'Reveal navigation',
                    onPressed: onReveal ?? () {},
                  ),
                  action: withAction
                      ? DMobileDockAction(
                          icon: const Icon(Icons.add),
                          label: 'New topic',
                          onPressed: () {},
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    testWidgets(
      'actionless dock fills the capsule with navigation ($direction)',
      (tester) async {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            fixture(withAction: false, direction: direction, scale: scale),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DMobileDockAction), findsNothing);
          final surface = tester.getRect(
            find.byKey(const ValueKey('mobile-dock-surface')),
          );
          final more = tester.getRect(find.byKey(const ValueKey('more')));
          if (direction == TextDirection.ltr) {
            expect(more.right, closeTo(surface.right - 6, .01));
          } else {
            expect(more.left, closeTo(surface.left + 6, .01));
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final brightness in Brightness.values) {
    for (final material in DAppearanceMaterial.values) {
      testWidgets(
        'capsule surrounds controls with its stock material ($brightness, $material)',
        (tester) async {
          final theme = DMaterialTheme.apply(
            brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
            material,
          );
          await tester.pumpWidget(fixture(theme: theme));
          await tester.pumpAndSettle();
          final capsule = find.byKey(const ValueKey('mobile-dock-surface'));
          final surface = tester.getRect(capsule);
          final destination = tester.getRect(
            find.byKey(const ValueKey('Topics')),
          );
          final action = tester.getRect(find.byType(DMobileDockAction));
          expect(surface.height, 62);
          expect(destination.height, 50);
          expect(destination.top - surface.top, 6);
          expect(surface.bottom - destination.bottom, 6);
          expect(surface.right - action.right, 6);
          if (material == DAppearanceMaterial.liquidGlass) {
            final lens = tester.widget<LiquidGlassLens>(
              find
                  .descendant(
                    of: capsule,
                    matching: find.byType(LiquidGlassLens),
                  )
                  .first,
            );
            expectStockGlass(
              lens.style,
              LiquidGlassTabBar.defaultStyle,
              surface.height,
            );
            expect(
              tester.widget<AnimatedContainer>(capsule).decoration,
              isNull,
            );
            expect(find.byType(DMaterialSurface), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'glass dock keeps stock material and selected destination uses button lighting; inactive items stay clear',
    (tester) async {
      final effects = find.byType(LiquidGlassLens);
      final theme = DMaterialTheme.apply(
        AppTheme.dark,
        DAppearanceMaterial.liquidGlass,
      );
      await tester.pumpWidget(fixture(theme: theme));
      await tester.pumpAndSettle();
      // One shared dock lens, one selected destination and the compose action.
      expect(effects, findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('Topics')),
          matching: effects,
        ),
        findsOneWidget,
      );
      for (final name in ['Start', 'Chat']) {
        expect(
          find.descendant(of: find.byKey(ValueKey(name)), matching: effects),
          findsNothing,
        );
      }
      const itemStyle = LiquidGlassTabItemStyle();
      for (final (name, selected) in [('Start', false), ('Topics', true)]) {
        final item = find.byKey(ValueKey(name));
        final icon = find.descendant(
          of: item,
          matching: find.byIcon(Icons.forum),
        );
        final iconTheme = IconTheme.of(tester.element(icon));
        expect(iconTheme.size, itemStyle.iconSize);
        expect(
          iconTheme.color,
          const LiquidGlassAdaptivity().contentColorOnDark,
        );
        final text = tester.widget<Text>(find.text(name));
        final textStyle = DefaultTextStyle.of(
          tester.element(find.text(name)),
        ).style.merge(text.style);
        expect(textStyle.fontSize, itemStyle.labelFontSize);
        expect(
          textStyle.fontWeight,
          itemStyle.fontWeightFor(selected: selected),
        );
      }
      final bounds = tester.getRect(find.byKey(const ValueKey('Topics')));
      await tester.pumpWidget(fixture(theme: theme, highContrast: true));
      await tester.pumpAndSettle();
      expect(effects, findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('Topics'))), bounds);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'stock dock content follows the package light and dark palettes',
    (tester) async {
      const adaptive = LiquidGlassAdaptivity();
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          fixture(
            theme: DMaterialTheme.apply(
              brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
              DAppearanceMaterial.liquidGlass,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final name in ['Start', 'Topics']) {
          final glyph = find.descendant(
            of: find.byKey(ValueKey(name)),
            matching: find.byIcon(Icons.forum),
          );
          expect(
            IconTheme.of(tester.element(glyph)).color,
            brightness == Brightness.dark
                ? adaptive.contentColorOnDark
                : adaptive.contentColorOnLight,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('glass spring reverses smoothly and reduced motion snaps', (
    tester,
  ) async {
    final theme = DMaterialTheme.apply(
      AppTheme.dark,
      DAppearanceMaterial.liquidGlass,
    );
    final surface = find.byKey(const ValueKey('mobile-dock-surface'));
    await tester.pumpWidget(fixture(theme: theme));
    await tester.pumpAndSettle();
    final open = tester.getSize(surface);
    final selectedCenter = tester
        .getCenter(find.byKey(const ValueKey('Topics')))
        .dx;
    final closedCenter = tester.getRect(surface).left + 24;
    await tester.pumpWidget(fixture(theme: theme, collapsed: true));
    await tester.pump(const Duration(milliseconds: 90));
    final midway = tester.getSize(surface);
    expect(midway.width, inExclusiveRange(48, open.width));
    expect(midway.height, inExclusiveRange(48, open.height));
    expect(
      tester.getCenter(find.byKey(const ValueKey('reveal'))).dx,
      inExclusiveRange(closedCenter, selectedCenter),
    );
    expect(find.byKey(const ValueKey('Start')).hitTestable(), findsNothing);
    await tester.pumpWidget(fixture(theme: theme));
    expect(tester.getSize(surface), midway);
    await tester.pumpAndSettle();
    expect(tester.getSize(surface), open);
    expect(find.byKey(const ValueKey('Start')).hitTestable(), findsOneWidget);
    await tester.pumpWidget(fixture(theme: theme, collapsed: true));
    await tester.pumpAndSettle();
    expect(tester.getSize(surface), const Size(48, 48));
    expect(find.byKey(const ValueKey('reveal')).hitTestable(), findsOneWidget);
    await tester.pumpWidget(fixture(theme: theme, reducedMotion: true));
    await tester.pump();
    expect(tester.getSize(surface), open);
    expect(tester.takeException(), isNull);
  });
  testWidgets('glass controls keep button lighting during the spring morph', (
    tester,
  ) async {
    final theme = DMaterialTheme.apply(
      AppTheme.dark,
      DAppearanceMaterial.liquidGlass,
    );
    final controls = [
      find.byKey(const ValueKey('Topics')),
      find.byType(DMobileDockAction),
    ];
    await tester.pumpWidget(fixture(theme: theme));
    await tester.pumpAndSettle();
    final widths = controls
        .map(tester.getRect)
        .map((rect) => rect.width)
        .toList();
    await tester.pumpWidget(fixture(theme: theme, collapsed: true));
    await tester.pump(const Duration(milliseconds: 16));
    for (var item = 0; item < controls.length; item++) {
      final lens = tester.widget<LiquidGlassLens>(
        find.descendant(
          of: controls[item],
          matching: find.byType(LiquidGlassLens),
        ),
      );
      expectStockGlass(lens.style, expectedButtonGlassStyle, 50);
      RenderObject? ancestor = tester.renderObject(controls[item]);
      while (ancestor != null) {
        if (ancestor is RenderOpacity) {
          expect(ancestor.opacity, anyOf(0.0, 1.0));
        } else if (ancestor is RenderAnimatedOpacity) {
          expect(ancestor.opacity.value, anyOf(0.0, 1.0));
        }
        ancestor = ancestor.parent;
      }
      expect(tester.getRect(controls[item]).width, lessThan(widths[item]));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final direction in TextDirection.values) {
    testWidgets(
      'measures labels and badges, keeps overflow and action visible ($direction)',
      (tester) async {
        var shown = 0;
        await tester.pumpWidget(
          fixture(direction: direction, onOverflow: (n) => shown = n),
        );
        await tester.pumpAndSettle();
        expect(shown, 3);
        final surface = tester.getRect(
          find.byKey(const ValueKey('mobile-dock-surface')),
        );
        for (final key in ['Start', 'Topics', 'Chat', 'more']) {
          final item = find.byKey(ValueKey(key));
          expect(item.hitTestable(), findsOneWidget);
          final rect = tester.getRect(item);
          expect(rect.left, greaterThanOrEqualTo(surface.left));
          expect(rect.right, lessThanOrEqualTo(surface.right));
        }
        expect(find.byKey(const ValueKey('Inbox')).hitTestable(), findsNothing);
        expect(find.text('More'), findsNothing);
        final semantics = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('more')))
              .getSemanticsData()
              .label,
          'More',
        );
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('folded dock retains only a bounded reveal target', (
    tester,
  ) async {
    var revealed = 0;
    await tester.pumpWidget(fixture());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      fixture(collapsed: true, onReveal: () => revealed++),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-dock-surface'))),
      const Size(48, 48),
    );
    expect(find.byKey(const ValueKey('Start')).hitTestable(), findsNothing);
    expect(find.byKey(const ValueKey('reveal')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reveal')));
    expect(revealed, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'large text spills destinations without clipping action or More',
    (tester) async {
      for (final width in [320.0, 430.0, 700.0]) {
        await tester.pumpWidget(fixture(width: width, scale: 2));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('more')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(DMobileDockAction).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

void expectStockGlass(
  LiquidGlassStyle actual,
  LiquidGlassStyle stock,
  double height,
) {
  expect(actual.color, stock.color);
  expect(actual.blur, stock.blur);
  expect(actual.saturation, stock.saturation);
  expect(actual.specular, stock.specular);
  expect(actual.glow, stock.glow);
  expect(actual.shadow, stock.shadow);
  expect(actual.refractionIndex, stock.refractionIndex);
  expect(actual.refractionWidth, stock.refractionWidth);
  expect(actual.magnification, stock.magnification);
  expect(actual.dispersion, stock.dispersion);
  expect(actual.adaptivity, stock.adaptivity);
  expect(actual.liteGlass, stock.liteGlass);
  expect(actual.shape!.cornerStyle, LiquidGlassCornerStyle.roundedRectangle);
  expect(actual.shape!.cornerRadius, height / 2);
}
