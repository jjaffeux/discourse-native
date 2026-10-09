import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reduced in [false, true]) {
    for (final shared in [false, true]) {
      testWidgets(
        'suppression retains scroll geometry and releases obstruction '
        '(reduced: $reduced, shared: $shared)',
        (tester) async {
          final covered = ValueNotifier(false);
          final scroll = ScrollController(initialScrollOffset: 120);
          addTearDown(covered.dispose);
          addTearDown(scroll.dispose);
          late DPageHeaderGeometry geometry;
          var bodyBuilds = 0;
          var activated = 0;
          final surface = DPageSurface.scrollable(
            framed: false,
            headerSuppressed: covered,
            header: SizedBox(
              height: 80,
              child: DButton(
                label: const Text('Header action'),
                onPressed: () {},
              ),
            ),
            headerControls: SizedBox(
              height: 40,
              child: DButton(
                label: const Text('Persistent action'),
                onPressed: () {},
              ),
            ),
            bodyBuilder: (_, header) {
              geometry = header;
              bodyBuilds++;
              return CustomScrollView(
                key: const ValueKey('viewport'),
                controller: scroll,
                slivers: [
                  SliverToBoxAdapter(child: header.spacer),
                  SliverToBoxAdapter(
                    child: DButton(
                      label: const Text('Body action'),
                      onPressed: () => activated++,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 1200)),
                ],
              );
            },
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: shared
                    ? DScrollChrome(
                        identity: 'page',
                        footerBuilder: (_) => const SizedBox.shrink(),
                        child: surface,
                      )
                    : surface,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final position = scroll.position;
          final extent = position.maxScrollExtent;
          final rect = tester.getRect(find.byKey(const ValueKey('viewport')));
          final rowY = tester.getTopLeft(find.text('Body action')).dy;
          expect(geometry.naturalExtent, 120);
          expect(geometry.visibleExtent, 120);
          expect(find.text('Body action').hitTestable(), findsNothing);
          covered.value = true;
          await tester.pump();
          if (reduced) expect(geometry.visibleExtent, 0);
          await tester.pumpAndSettle();
          expect(geometry.visibleExtent, 0);
          expect(geometry.naturalExtent, 120);
          expect(find.text('Header action').hitTestable(), findsNothing);
          expect(find.text('Persistent action').hitTestable(), findsNothing);
          expect(tester.getRect(find.byKey(const ValueKey('viewport'))), rect);
          expect(scroll.position, same(position));
          expect(position.maxScrollExtent, extent);
          expect(tester.getTopLeft(find.text('Body action')).dy, rowY);
          await tester.tap(find.text('Body action'));
          expect(activated, 1);
          covered.value = false;
          await tester.pumpAndSettle();
          expect(geometry.visibleExtent, 120);
          expect(find.text('Header action').hitTestable(), findsOneWidget);
          expect(bodyBuilds, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
