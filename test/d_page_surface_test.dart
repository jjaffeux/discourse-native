import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/page_surface_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _header = ValueKey('page-header');
const _viewport = ValueKey('page-viewport');
const _tabs = ValueKey('page-tabs');
const _footer = ValueKey('page-footer');

Future<void> _wheel(WidgetTester tester, Finder target, double delta) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(target),
      scrollDelta: Offset(0, delta / 2),
    ),
  );
  await tester.pump();
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(target),
      scrollDelta: Offset(0, delta / 2),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _list({ScrollController? controller}) => ListView.builder(
  key: _viewport,
  controller: controller,
  itemExtent: 50,
  itemCount: 100,
  itemBuilder: (_, index) => Text('Row $index'),
);

void main() {
  testWidgets('a phone draws the fields under a page title 44 tall', (
    tester,
  ) async {
    for (final (platform, height) in [
      (TargetPlatform.iOS, kDTouchTargetExtent),
      (TargetPlatform.android, kDTouchTargetExtent),
      (TargetPlatform.macOS, 35.5),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          themeAnimationStyle: AnimationStyle.noAnimation,
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 300,
                  child: DInput(
                    key: const ValueKey('elsewhere'),
                    size: DControlSize.field,
                    hintText: 'Search',
                  ),
                ),
                Expanded(
                  child: DPageSurface.headed(
                    title: const Text('Users'),
                    controls: DInput(
                      key: const ValueKey('page-field'),
                      size: DControlSize.field,
                      hintText: 'Filter users',
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const ValueKey('page-field'))).height,
        height,
        reason: '$platform',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('elsewhere'))).height,
        35.5,
        reason: '$platform',
      );
    }
  });

  for (final withHeader in [false, true]) {
    testWidgets('floating footer resizes over a stable full-height body '
        '(header: $withHeader)', (tester) async {
      final height = ValueNotifier(60.0);
      addTearDown(height.dispose);
      late DPageHeaderGeometry geometry;
      var bodyBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 360,
              child: DPageSurface.scrollable(
                framed: false,
                floatingFooter: true,
                header: withHeader ? const SizedBox(height: 50) : null,
                footer: ValueListenableBuilder(
                  valueListenable: height,
                  builder: (_, value, _) =>
                      SizedBox(key: _footer, height: value),
                ),
                bodyBuilder: (_, measured) {
                  geometry = measured;
                  bodyBuilds++;
                  return Stack(
                    key: _viewport,
                    children: [
                      const Positioned.fill(child: Text('Transcript')),
                      Positioned(
                        bottom: 12,
                        left: 0,
                        child: measured.footerInset(
                          const SizedBox(
                            key: ValueKey('footer-overlay-control'),
                            width: 24,
                            height: 24,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      final viewport = find.byKey(_viewport);
      final originalElement = tester.element(viewport);
      final bounds = tester.getRect(viewport);
      final control = find.byKey(const ValueKey('footer-overlay-control'));
      expect(bounds.height, 360);
      expect(geometry.footerExtent, 60);
      expect(geometry.naturalExtent, withHeader ? 50 : 0);
      expect(
        tester.getBottomLeft(control).dy,
        tester.getTopLeft(find.byKey(_footer)).dy - 12,
      );

      for (final value in [130.0, 35.0]) {
        height.value = value;
        await tester.pump();
        expect(tester.getRect(viewport), bounds);
        expect(tester.element(viewport), same(originalElement));
        expect(bodyBuilds, 1);
        expect(geometry.footerExtent, value);
        expect(
          tester.getBottomLeft(control).dy,
          tester.getTopLeft(find.byKey(_footer)).dy - 12,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('optional floating footer clears its measured obstruction', (
    tester,
  ) async {
    late StateSetter rebuild;
    late DPageHeaderGeometry geometry;
    var showFooter = true;
    var floatingFooter = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return DPageSurface.scrollable(
              framed: false,
              floatingFooter: floatingFooter,
              footer: showFooter ? const SizedBox(height: 60) : null,
              bodyBuilder: (_, measured) {
                geometry = measured;
                return const SizedBox.expand(key: _viewport);
              },
            );
          },
        ),
      ),
    );
    expect(geometry.footerExtent, 60);
    rebuild(() => showFooter = false);
    await tester.pump();
    expect(geometry.footerExtent, 0);
    rebuild(() => showFooter = true);
    await tester.pump();
    expect(geometry.footerExtent, 60);
    rebuild(() => floatingFooter = false);
    await tester.pump();
    expect(geometry.footerExtent, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fixed footer remains the default for scrollable pages', (
    tester,
  ) async {
    late DPageHeaderGeometry geometry;
    await tester.pumpWidget(
      MaterialApp(
        home: DPageSurface.scrollable(
          framed: false,
          header: const SizedBox(height: 50),
          footer: const SizedBox(key: _footer, height: 60),
          bodyBuilder: (_, measured) {
            geometry = measured;
            return const SizedBox.expand(key: _viewport);
          },
        ),
      ),
    );
    expect(
      tester.getBottomLeft(find.byKey(_viewport)).dy,
      tester.getTopLeft(find.byKey(_footer)).dy,
    );
    expect(geometry.footerExtent, 0);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets('existing sliver viewport stays fixed while its header moves '
        '(reduced motion: $reducedMotion)', (tester) async {
      final scroll = ScrollController(initialScrollOffset: 600);
      addTearDown(scroll.dispose);
      late DPageHeaderGeometry geometry;
      var bodyBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: DPageSurface.scrollable(
              framed: false,
              hideHeaderOnScroll: true,
              header: const SizedBox(key: _header, height: 80),
              footer: const SizedBox(key: _footer, height: 40),
              bodyBuilder: (context, header) {
                geometry = header;
                bodyBuilds++;
                return CustomScrollView(
                  key: _viewport,
                  controller: scroll,
                  slivers: [
                    SliverToBoxAdapter(child: header.spacer),
                    SliverFixedExtentList.builder(
                      itemExtent: 50,
                      itemCount: 100,
                      itemBuilder: (_, index) => Text('Row $index'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final viewport = find.byKey(_viewport);
      final rect = tester.getRect(viewport);
      final position = scroll.position;
      final maxExtent = position.maxScrollExtent;
      final row = find.text('Row 14');
      final before = tester.getTopLeft(row).dy;
      expect(geometry.naturalExtent, 80);
      expect(geometry.visibleExtent, 80);
      expect(rect.top, 0);
      expect(rect.bottom, tester.getTopLeft(find.byKey(_footer)).dy);

      Future<void> move(double delta) async {
        await tester.pump(const Duration(milliseconds: 450));
        final rowBefore = tester.getTopLeft(row).dy;
        final offsetBefore = scroll.offset;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(viewport),
            scrollDelta: Offset(0, delta),
          ),
        );
        await tester.pump();
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getRect(viewport), rect);
          expect(scroll.position, same(position));
          expect(position.maxScrollExtent, maxExtent);
          expect(scroll.offset, offsetBefore + delta);
          expect(tester.getTopLeft(row).dy, rowBefore - delta);
          expect(geometry.naturalExtent, 80);
        }
      }

      await move(160);
      await tester.pumpAndSettle();
      expect(geometry.visibleExtent, 0);
      await move(-80);
      await move(-80);
      await tester.pumpAndSettle();
      expect(geometry.visibleExtent, 80);
      expect(tester.getTopLeft(row).dy, before);
      expect(bodyBuilds, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scrollable page measures a resized header in the same frame', (
    tester,
  ) async {
    late StateSetter resize;
    var height = 80.0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            resize = setState;
            return DPageSurface.scrollable(
              framed: false,
              header: SizedBox(height: height),
              bodyBuilder: (_, header) => CustomScrollView(
                key: _viewport,
                slivers: [
                  SliverToBoxAdapter(child: header.spacer),
                  const SliverToBoxAdapter(child: Text('First post')),
                ],
              ),
            );
          },
        ),
      ),
    );
    expect(tester.getTopLeft(find.text('First post')).dy, 80);
    final rect = tester.getRect(find.byKey(_viewport));
    resize(() => height = 120);
    await tester.pump();
    expect(tester.getTopLeft(find.text('First post')).dy, 120);
    expect(tester.getRect(find.byKey(_viewport)), rect);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    testWidgets('headed title leads with its icon in the muted foreground '
        '(${direction.name})', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: DPageSurface.headed(
              icon: DIcons.gear,
              title: const Text('Settings'),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      final icon = find.byWidgetPredicate(
        (widget) => widget is DIcon && widget.icon == DIcons.gear,
      );
      expect(icon, findsOneWidget);
      final glyph = tester.widget<DIcon>(icon);
      expect(glyph.size, 16);
      expect(glyph.color, DTokens.of(tester.element(icon)).mutedForeground);
      final mark = tester.getRect(icon);
      final title = tester.getRect(find.text('Settings'));
      expect(mark.center.dy, closeTo(title.center.dy, 1));
      if (direction == TextDirection.ltr) {
        expect(title.left - mark.right, closeTo(9, .01));
      } else {
        expect(mark.left - title.right, closeTo(9, .01));
      }
    });
  }

  testWidgets('persistent header controls move while the body stays anchored', (
    tester,
  ) async {
    var pressed = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DPageSurface(
          framed: false,
          hideHeaderOnScroll: true,
          header: const SizedBox(
            key: _header,
            height: 64,
            child: Text('Forum'),
          ),
          headerControls: DButton(
            key: const ValueKey('persistent-controls'),
            label: const Text('Filters'),
            onPressed: () => pressed++,
          ),
          child: _list(controller: scroll),
        ),
      ),
    );
    final controls = find.byKey(const ValueKey('persistent-controls'));
    final top = tester.getTopLeft(controls).dy;
    final viewport = tester.getRect(find.byKey(_viewport));
    await _wheel(tester, find.byKey(_viewport), 200);
    expect(find.text('Forum').hitTestable(), findsNothing);
    expect(tester.getTopLeft(controls).dy, closeTo(top - 64, .01));
    expect(tester.getRect(find.byKey(_viewport)), viewport);
    await tester.tap(controls);
    await tester.pumpAndSettle();
    expect(pressed, 1);
    await _wheel(tester, find.byKey(_viewport), -200);
    expect(tester.getTopLeft(find.byKey(_header)).dy, closeTo(0, .01));
    expect(tester.getTopLeft(controls).dy, closeTo(top, .01));
  });

  testWidgets('borderless page retains fill, clipping and footer divider', (
    tester,
  ) async {
    const fill = Color(0xff334455);
    for (final border in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: DPageSurface(
            border: border,
            backgroundColor: fill,
            footer: const DCardFooter(rounded: true, child: Text('Footer')),
            child: const Text('Page'),
          ),
        ),
      );
      final card = find.byType(DCard);
      final outline = tester.widget<DecoratedBox>(
        find.descendant(of: card, matching: find.byType(DecoratedBox)).first,
      );
      expect((outline.decoration as BoxDecoration).border != null, border);
      final material = tester.widget<Material>(
        find.descendant(of: card, matching: find.byType(Material)).first,
      );
      expect(material.color, fill);
      expect(material.clipBehavior, Clip.antiAlias);
      expect(material.borderRadius, BorderRadius.circular(DRadius.panel));
      final footerOutline = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(DCardFooter),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((footerOutline.decoration as BoxDecoration).border!.top.width, 1);
      expect(find.text('Footer'), findsOneWidget);
      expect(find.text('Page'), findsOneWidget);
    }
  });

  testWidgets('framed pages pass corner geometry to the Native card', (
    tester,
  ) async {
    const radius = BorderRadius.only(bottomRight: Radius.circular(10));
    await tester.pumpWidget(
      const MaterialApp(
        home: DPageSurface(borderRadius: radius, child: Text('Page')),
      ),
    );
    expect(tester.widget<DCard>(find.byType(DCard)).borderRadius, radius);
    await tester.pumpWidget(
      const MaterialApp(
        home: DPageSurface(
          framed: false,
          borderRadius: radius,
          child: Text('Page'),
        ),
      ),
    );
    expect(find.byType(DCard), findsNothing);
  });

  testWidgets('custom page fill retains its frame and descendant theme', (
    tester,
  ) async {
    const fill = Color(0x664488cc);
    Color? descendantBackground;
    await tester.pumpWidget(
      MaterialApp(
        home: DPageSurface(
          backgroundColor: fill,
          child: Builder(
            builder: (context) {
              descendantBackground = DTokens.of(context).background;
              return const Text('Page content');
            },
          ),
        ),
      ),
    );
    final card = find.byType(DCard);
    final material = tester.widget<Material>(
      find.descendant(of: card, matching: find.byType(Material)).first,
    );
    expect(material.color, fill);
    expect(material.clipBehavior, Clip.antiAlias);
    expect(descendantBackground!.a, 1);
    final frame = tester.widget<DecoratedBox>(
      find.descendant(of: card, matching: find.byType(DecoratedBox)).first,
    );
    expect((frame.decoration as BoxDecoration).border, isNotNull);
    expect(frame.position, DecorationPosition.foreground);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'page owns width, fixed tabs and footer while retaining the body',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      Future<void> mount({
        bool limited = false,
        String identity = 'users',
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DPageSurface(
                hideHeaderOnScroll: true,
                identity: identity,
                limitContentSize: limited,
                tabs: const SizedBox(key: _tabs, height: 40),
                header: const SizedBox(
                  key: _header,
                  height: 80,
                  child: ColoredBox(color: Colors.blue),
                ),
                footer: const SizedBox(key: _footer, height: 40),
                child: DPageReadingLane(
                  builder: (context, lane) => ListView.builder(
                    key: _viewport,
                    controller: scroll,
                    padding: lane.padding,
                    itemExtent: 50,
                    itemCount: 100,
                    itemBuilder: (_, index) => SizedBox(
                      key: ValueKey('row-$index'),
                      child: Text('Row $index'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      expect(find.byType(DCard), findsOneWidget);
      final viewport = tester.element(find.byKey(_viewport));
      final tabs = tester.getRect(find.byKey(_tabs));
      final footer = tester.getRect(find.byKey(_footer));
      expect(tester.getSize(find.byKey(const ValueKey('row-0'))).width, 1400);
      await _wheel(tester, find.byKey(_viewport), 160);
      expect(find.byKey(_header).hitTestable(), findsNothing);
      expect(tester.getRect(find.byKey(_tabs)), tabs);
      expect(tester.getRect(find.byKey(_footer)), footer);
      await mount(limited: true);
      expect(tester.element(find.byKey(_viewport)), same(viewport));
      expect(scroll.offset, 160);
      expect(tester.getSize(find.byKey(_tabs)).width, 1400);
      expect(tester.getSize(find.byKey(_header)).width, 825);
      expect(tester.getSize(find.byKey(_viewport)).width, 1400);
      expect(tester.getSize(find.byKey(_footer)).width, 825);
      expect(tester.getRect(find.byKey(_header)).center.dx, 700);
      expect(tester.getSize(find.byKey(const ValueKey('row-4'))).width, 825);
      expect(
        tester.getRect(find.byKey(const ValueKey('row-4'))).center.dx,
        700,
      );
      await _wheel(tester, find.byKey(_viewport), -100);
      expect(find.byKey(_header).hitTestable(), findsOneWidget);
      await _wheel(tester, find.byKey(_viewport), 80);
      await mount(limited: true, identity: 'drafts');
      expect(find.byKey(_header).hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'vertical table scrolling inside a horizontal viewport retracts',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DPageSurface(
              hideHeaderOnScroll: true,
              header: const SizedBox(
                key: _header,
                height: 80,
                child: ColoredBox(color: Colors.blue),
              ),
              child: LayoutBuilder(
                builder: (_, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 1200,
                    height: constraints.maxHeight,
                    child: _list(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _wheel(tester, find.byKey(_viewport), 160);
      expect(find.byKey(_header).hitTestable(), findsNothing);
      await _wheel(tester, find.byKey(_viewport), -100);
      expect(find.byKey(_header).hitTestable(), findsOneWidget);
    },
  );

  testWidgets('embedded vertical scrolling does not retract the page header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DPageSurface(
            hideHeaderOnScroll: true,
            header: const SizedBox(
              key: _header,
              height: 80,
              child: ColoredBox(color: Colors.blue),
            ),
            child: ListView(
              children: [
                SizedBox(height: 200, child: _list()),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _wheel(tester, find.byKey(_viewport), 100);
    expect(find.byKey(_header).hitTestable(), findsOneWidget);
  });

  testWidgets(
    'headers stay fixed by default and reappear when hiding is disabled',
    (tester) async {
      Future<void> mount({bool hide = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DPageSurface(
                hideHeaderOnScroll: hide,
                header: const SizedBox(
                  key: _header,
                  height: 80,
                  child: ColoredBox(color: Colors.blue),
                ),
                child: _list(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      final viewport = tester.element(find.byKey(_viewport));
      await _wheel(tester, find.byKey(_viewport), 160);
      expect(find.byKey(_header).hitTestable(), findsOneWidget);
      await mount(hide: true);
      await _wheel(tester, find.byKey(_viewport), 160);
      expect(find.byKey(_header).hitTestable(), findsNothing);
      await mount();
      expect(find.byKey(_header).hitTestable(), findsOneWidget);
      expect(tester.element(find.byKey(_viewport)), same(viewport));
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('styleguide supports narrow large text in $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Builder(builder: pageSurfaceExamples.examples.last.builder),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open topic'));
      await tester.pumpAndSettle();
      expect(find.text('Topic · 1'), findsOneWidget);
      await tester.tap(find.text('Limit content width'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
