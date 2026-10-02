import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum _PageKind { column, scrollBody, slivers }

const _header = ValueKey('threshold-header');

Future<void> _mount(
  WidgetTester tester, {
  required _PageKind kind,
  required double contentHeight,
  double height = 600,
  bool reverse = false,
}) async {
  const header = SizedBox(key: _header, height: 80, child: Text('Header'));
  final content = SizedBox(
    height: contentHeight - (kind == _PageKind.column ? 0 : 80),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          height: height,
          child: switch (kind) {
            _PageKind.column => DPageSurface(
              framed: false,
              hideHeaderOnScroll: true,
              header: header,
              child: ListView(
                reverse: reverse,
                padding: EdgeInsets.zero,
                children: [content],
              ),
            ),
            _PageKind.scrollBody => DPageSurface(
              framed: false,
              hideHeaderOnScroll: true,
              scrollBody: true,
              header: header,
              child: content,
            ),
            _PageKind.slivers => DPageSurface.scrollable(
              framed: false,
              hideHeaderOnScroll: true,
              header: header,
              bodyBuilder: (_, geometry) => CustomScrollView(
                reverse: reverse,
                slivers: [
                  SliverToBoxAdapter(child: geometry.spacer),
                  SliverToBoxAdapter(child: content),
                ],
              ),
            ),
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byType(Scrollable)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in _PageKind.values) {
    for (final reverse in [false, if (kind != _PageKind.scrollBody) true]) {
      for (final ratio in [1.99, 2.0, 2.01]) {
        testWidgets('$kind toggles only at two viewports '
            '(ratio: $ratio, reverse: $reverse)', (tester) async {
          final viewport = kind == _PageKind.column ? 520.0 : 600.0;
          await _mount(
            tester,
            kind: kind,
            reverse: reverse,
            contentHeight: viewport * ratio,
          );
          final position = tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position;
          expect(position.viewportDimension, viewport);
          if (reverse) {
            position.jumpTo(position.maxScrollExtent - 100);
            await tester.pumpAndSettle();
          }
          final before = position.pixels;
          await _wheel(tester, 8);
          expect(position.pixels, before + (reverse ? -8 : 8));
          expect(
            find.byKey(_header).hitTestable(),
            ratio < 2 ? findsOneWidget : findsNothing,
          );
          // Continued input must not make a column header cross its own cutoff.
          await _wheel(tester, 8);
          expect(
            find.byKey(_header).hitTestable(),
            ratio < 2 ? findsOneWidget : findsNothing,
          );
          await _wheel(tester, -8);
          expect(find.byKey(_header).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final resizeViewport in [false, true]) {
      testWidgets('$kind reveals when content becomes short '
          '(resize viewport: $resizeViewport)', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _mount(tester, kind: kind, contentHeight: 1300);
        await _wheel(tester, 8);
        expect(find.byKey(_header).hitTestable(), findsNothing);

        await _mount(
          tester,
          kind: kind,
          contentHeight: resizeViewport ? 1300 : 1000,
          height: resizeViewport ? 740 : 600,
        );
        expect(find.byKey(_header).hitTestable(), findsOneWidget);
        await _wheel(tester, 8);
        expect(find.byKey(_header).hitTestable(), findsOneWidget);

        await _mount(tester, kind: kind, contentHeight: 1300);
        expect(find.byKey(_header).hitTestable(), findsOneWidget);
        await _wheel(tester, 8);
        expect(find.byKey(_header).hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
