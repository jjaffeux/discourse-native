import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a resized full header updates its reserved space', (
    tester,
  ) async {
    late DPageHeaderGeometry geometry;
    Future<void> pump(double height) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DPageSurface.scrollable(
              framed: false,
              header: SizedBox(height: height, child: const Text('Topics')),
              bodyBuilder: (_, header) {
                geometry = header;
                return ListView(
                  children: [
                    header.spacer,
                    const SizedBox(key: ValueKey('first-row'), height: 60),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(180);
    expect(geometry.naturalExtent, 180);
    await pump(100);
    expect(geometry.naturalExtent, 100);
    expect(tester.getTopLeft(find.byKey(const ValueKey('first-row'))).dy, 100);
    expect(tester.takeException(), isNull);
  });
  for (final reverse in [false, true]) {
    testWidgets(
      'measures the first compact cutoff from the physical top (reverse: $reverse)',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        late DPageHeaderGeometry geometry;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DPageSurface.scrollable(
                framed: false,
                hideHeaderOnScroll: true,
                measureCompactHeader: true,
                header: const SizedBox(
                  key: ValueKey('full'),
                  height: 180,
                  child: Text('Full title'),
                ),
                compactHeader: SizedBox(
                  key: const ValueKey('compact'),
                  height: 47,
                  child: DButton(
                    label: const Text('Compact action'),
                    onPressed: () {},
                  ),
                ),
                bodyBuilder: (_, value) {
                  geometry = value;
                  return ListView(
                    controller: scroll,
                    reverse: reverse,
                    children: [
                      if (!reverse) value.spacer,
                      for (var i = 0; i < 80; i++) const SizedBox(height: 60),
                      if (reverse) value.spacer,
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (reverse) {
          expect(find.byKey(const ValueKey('compact')), findsOneWidget);
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const ValueKey('full')), findsOneWidget);
        expect(find.text('Compact action'), findsNothing);
        expect(
          find.text('Compact action', skipOffstage: false),
          findsOneWidget,
        );
        final origin = reverse ? scroll.position.maxScrollExtent : 0.0;
        scroll.jumpTo(origin + (reverse ? -120 : 120));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('full')),
          findsOneWidget,
          reason:
              '47px compact header starts after 180 - 47px, not the 76px estimate',
        );
        scroll.jumpTo(origin + (reverse ? -134 : 134));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('compact')), findsOneWidget);
        expect(find.byKey(const ValueKey('full')), findsNothing);
        expect(geometry.naturalExtent, 180);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('remeasures compact layout after width and text scale change', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    Future<void> pump(double width, double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: DPageSurface.scrollable(
                    framed: false,
                    hideHeaderOnScroll: true,
                    measureCompactHeader: true,
                    header: const SizedBox(
                      key: ValueKey('full'),
                      height: 240,
                      child: Text('Full'),
                    ),
                    compactHeader: LayoutBuilder(
                      builder: (context, constraints) => SizedBox(
                        key: const ValueKey('compact'),
                        height: constraints.maxWidth < 400
                            ? MediaQuery.textScalerOf(context).scale(50)
                            : 47,
                        child: const Text('Compact'),
                      ),
                    ),
                    bodyBuilder: (_, header) => ListView(
                      controller: scroll,
                      children: [header.spacer, const SizedBox(height: 4000)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(700, 1);
    scroll.jumpTo(180);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('full')), findsOneWidget);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await pump(320, 2);
    scroll.jumpTo(141);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('compact')),
      findsOneWidget,
      reason: 'The resized compact header is 100px, so the cutoff is 140px',
    );
    expect(tester.takeException(), isNull);
  });

  for (final shared in [false, true]) {
    testWidgets(
      'compact reader keeps its full spacer and viewport (shared: $shared)',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        late DPageHeaderGeometry geometry;
        final page = DPageSurface.scrollable(
          framed: false,
          hideHeaderOnScroll: true,
          header: const SizedBox(
            key: ValueKey('full'),
            height: 180,
            child: Text('Full topic title'),
          ),
          compactHeader: const SizedBox(
            key: ValueKey('compact'),
            height: 76,
            child: Text('Compact topic title'),
          ),
          bodyBuilder: (_, header) {
            geometry = header;
            return ListView(
              key: const ValueKey('viewport'),
              controller: scroll,
              children: [
                header.spacer,
                for (var i = 0; i < 80; i++)
                  SizedBox(height: 60, child: Text('Post $i')),
              ],
            );
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: shared
                  ? DScrollChrome(
                      identity: 'topic',
                      floatingFooter: true,
                      footerBuilder: (_) => const SizedBox(height: 60),
                      child: page,
                    )
                  : page,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byKey(const ValueKey('viewport')));
        expect(geometry.naturalExtent, 180);
        scroll.jumpTo(140);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('compact')), findsOneWidget);
        expect(find.byKey(const ValueKey('full')), findsNothing);
        expect(geometry.naturalExtent, 180);
        expect(
          tester.getRect(find.byKey(const ValueKey('viewport'))),
          viewport,
        );
        expect(scroll.offset, 140);
        scroll.jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('full')), findsOneWidget);
        expect(geometry.naturalExtent, 180);
        expect(scroll.offset, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
