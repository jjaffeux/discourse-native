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
