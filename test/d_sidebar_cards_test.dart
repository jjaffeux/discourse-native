import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final _controls = find.byKey(const ValueKey('controls'));
Finder _heading(String name) => find.byKey(ValueKey('heading-$name'));
Finder _trigger(String name) => find.byKey(ValueKey('trigger-$name'));

Future<void> _pump(
  WidgetTester tester, {
  double scale = 1,
  int rowCount = 12,
  Color? border,
  Brightness brightness = Brightness.light,
  int sheer = 0,
  Color? groundUnderHeadings,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = ThemeData(
    platform: TargetPlatform.iOS,
    brightness: brightness,
    extensions: [if (sheer > 0) DFrost(sheer: sheer)],
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('sidebar-card-capture'),
      child: MaterialApp(
        theme: border == null
            ? theme
            : theme.copyWith(
                extensions: [
                  ...theme.extensions.values,
                  DTokens.fromTheme(theme).copyWith(border: border),
                ],
              ),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: DSidebarProvider(
            mobileBreakpoint: 0,
            child: DSidebar(
              width: 390,
              collapsible: DSidebarCollapsible.none,
              footer: DSidebarFooter(
                child: Center(
                  child: SizedBox(
                    width: 60,
                    height: 20,
                    child: DCard(
                      key: const ValueKey('reference-rim'),
                      spacing: 0,
                      border: false,
                      borderRadius: BorderRadius.zero,
                      backgroundColor: DTokens.fromTheme(theme).panelBackground,
                      depth: DSurfaceDepth.rim,
                      child: const Expanded(child: SizedBox.shrink()),
                    ),
                  ),
                ),
              ),
              child: DSidebarContent.slivers(
                header: Padding(
                  padding: const EdgeInsets.all(6),
                  child: DButton(
                    key: const ValueKey('controls'),
                    label: const Text('Search'),
                    onPressed: () {},
                  ),
                ),
                slivers: [
                  for (final name in ['Forum', 'Categories', 'Tags'])
                    DCollapsible(
                      defaultOpen: true,
                      child: DSidebarGroup.sliver(
                        padding: EdgeInsets.zero,
                        header: DCollapsibleTrigger(
                          key: ValueKey('trigger-$name'),
                          child: DSidebarGroupLabel(
                            key: ValueKey('heading-$name'),
                            child: Text(name),
                          ),
                        ),
                        sliver: DCollapsibleContent.sliver(
                          sliver: groundUnderHeadings != null
                              ? SliverToBoxAdapter(
                                  child: ColoredBox(
                                    color: groundUnderHeadings,
                                    child: const SizedBox(height: 600),
                                  ),
                                )
                              : DSidebarMenu.sliverBuilder(
                                  itemCount: rowCount,
                                  itemBuilder: (context, index) =>
                                      DSidebarMenuButton(
                                        key: ValueKey('$name-$index'),
                                        onPressed: () {},
                                        child: Text('$name destination $index'),
                                      ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('held headings under a see-through palette', () {
    Finder frosts() => find.descendant(
      of: find.byType(DSidebar),
      matching: find.byType(BackdropFilter),
    );

    Future<void> hold(WidgetTester tester) async {
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .jumpTo(80);
      await tester.pumpAndSettle();
    }

    testWidgets('frost the rows passing under them, only while held', (
      tester,
    ) async {
      await _pump(tester, sheer: 10);
      expect(frosts(), findsNothing, reason: 'nothing is held at rest');
      await hold(tester);
      expect(frosts(), findsOneWidget);
      final heading = tester.getRect(_heading('Forum'));
      final frost = tester.getRect(frosts());
      expect(frost.width, 390);
      expect(frost.top, lessThanOrEqualTo(heading.top));
      expect(
        tester.widget<BackdropFilter>(frosts()).filter.toString(),
        contains('blur(26.0, 26.0'),
      );
    });

    testWidgets('are not frosted when the palette is opaque', (tester) async {
      await _pump(tester);
      await hold(tester);
      expect(frosts(), findsNothing);
    });

    testWidgets('lay their see-through fill once over what passes under', (
      tester,
    ) async {
      // A grey, which the frost's blur and saturation leave as it is.
      const ground = Color(0xFF000000);
      await _pump(tester, sheer: 30, groundUnderHeadings: ground);
      await hold(tester);
      final heading = tester.getRect(_heading('Forum'));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('sidebar-card-capture')),
      );
      final data = await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        } finally {
          image.dispose();
        }
      });
      final offset =
          (heading.center.dy.floor() * 390 + heading.center.dx.floor()) * 4;
      final drawn = [for (var i = 0; i < 3; i++) data!.getUint8(offset + i)];
      final fill = const DFrost(
        sheer: 30,
      ).panel(DTokens.of(tester.element(_heading('Forum'))).panelBackground);
      final once = Color.alphaBlend(fill, ground);
      final expected = [
        for (final channel in [once.r, once.g, once.b]) (channel * 255).round(),
      ];
      for (var i = 0; i < 3; i++) {
        expect(drawn[i], closeTo(expected[i], 2), reason: 'channel $i');
      }
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'section rims match the container in ${brightness.name} before and after pinning',
      (tester) async {
        const themeBorder = Color(0xFFE020D0);
        await _pump(
          tester,
          rowCount: 4,
          border: themeBorder,
          brightness: brightness,
        );
        final viewport = find.byType(CustomScrollView);
        final controller = tester
            .widget<CustomScrollView>(viewport)
            .controller!;

        Future<void> expectOutline() async {
          final heading = tester.getRect(_heading('Forum'));
          final next = tester.getRect(_heading('Categories'));
          final bottom = tester.getRect(find.byType(DSidebar)).bottom;
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('sidebar-card-capture')),
          );
          final data = await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            } finally {
              image.dispose();
            }
          });
          Color pixel(int x, int y) {
            final offset = (y * 390 + x) * 4;
            return Color.fromARGB(
              data!.getUint8(offset + 3),
              data.getUint8(offset),
              data.getUint8(offset + 1),
              data.getUint8(offset + 2),
            );
          }

          final reference = tester.getRect(
            find.byKey(const ValueKey('reference-rim')),
          );
          final referenceRim = pixel(
            reference.center.dx.floor(),
            reference.top.floor(),
          );
          final bodyY = (next.bottom + 20).floor();
          final border = pixel(0, bodyY);
          expect(border, isNot(themeBorder));
          for (final shift in [0, 8, 16, 24]) {
            expect(
              (border.toARGB32() >> shift) & 255,
              closeTo((referenceRim.toARGB32() >> shift) & 255, 1),
              reason:
                  'Matches the rendered container rim, allowing GPU rounding',
            );
          }
          expect(pixel(195, heading.top.floor()), border, reason: 'Top edge');
          expect(
            pixel(195, next.top.floor()),
            border,
            reason: 'The next sheet starts at its heading',
          );
          expect(
            pixel(389, bodyY),
            border,
            reason: 'Right edge beside the rows',
          );
          expect(
            pixel(195, bottom.floor() - 1),
            border,
            reason: 'The sheets share the sidebar bottom edge',
          );
          expect(
            pixel(195, next.top.floor() - 1),
            isNot(border),
            reason: 'The preceding sheet continues behind the next section',
          );
          expect(
            pixel(0, next.top.floor() + 1),
            border,
            reason: 'The preceding sheet shows behind the next rounded corner',
          );
          expect(
            pixel(195, (next.top + 80).floor()),
            isNot(border),
            reason: 'Scrolling leaves no stale sheet edge across the rows',
          );
        }

        await expectOutline();
        controller.jumpTo(80);
        await tester.pumpAndSettle();
        await expectOutline();
        controller.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(_trigger('Forum'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(_heading('Categories')).top -
              tester.getRect(_heading('Forum')).bottom,
          8,
        );
        await expectOutline();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'phone sidebar defaults are 40-point rows and 48-point headings',
    (tester) async {
      await _pump(tester);
      expect(tester.getSize(find.byKey(const ValueKey('Forum-0'))).height, 40);
      expect(tester.getSize(_heading('Forum')).height, 48);
      final controls = tester.getRect(_controls);
      final viewport = find.byType(CustomScrollView);
      final controller = tester.widget<CustomScrollView>(viewport).controller!;
      final top = controls.bottom + 6;
      controller.jumpTo(400);
      await tester.pumpAndSettle();
      expect(tester.getRect(_heading('Forum')).top, top);
      expect(tester.getRect(_controls), controls);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: controls.center,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(400));
      controller.jumpTo(520 + top);
      await tester.pumpAndSettle();
      expect(tester.getRect(_heading('Forum')).top, lessThan(top));
      expect(
        tester.getRect(_heading('Forum')).bottom,
        lessThanOrEqualTo(tester.getRect(_heading('Categories')).top),
      );
      controller.jumpTo(536 + top);
      await tester.pumpAndSettle();
      expect(tester.getRect(_heading('Categories')).top, top);
      controller.jumpTo(536);
      await tester.pumpAndSettle();
      await tester.tap(_trigger('Categories'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('Categories-0')).hitTestable(),
        findsNothing,
      );
      expect(tester.getRect(_heading('Tags')).top - top, 56);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone rich sidebar items use the existing 56-point row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: DItem(
              key: const ValueKey('conversation'),
              size: DItemSize.sm,
              shape: DItemShape.menu,
              selectionStyle: DItemSelectionStyle.sidebar,
              onPressed: () {},
              children: const [
                DItemContent(
                  children: [
                    DItemTitle(child: Text('Design')),
                    DItemDescription(child: Text('A new draft is ready')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('conversation'))).height,
      56,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large phone text preserves card disclosure and fixed controls', (
    tester,
  ) async {
    await _pump(tester, scale: 2);
    final controls = tester.getRect(_controls);
    final viewport = find.byType(CustomScrollView);
    await tester.drag(viewport, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getRect(_controls), controls);
    expect(_trigger('Forum').hitTestable(), findsOneWidget);
    await tester.tap(_trigger('Forum'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('Forum-0')).hitTestable(), findsNothing);
    expect(_trigger('Categories').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
