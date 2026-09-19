import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/page_surface_examples.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _header = ValueKey('page-header');
const _viewport = ValueKey('page-viewport');
const _tabs = ValueKey('page-tabs');
const _footer = ValueKey('page-footer');

Future<void> _wheel(WidgetTester tester, Finder target, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(target),
      scrollDelta: Offset(0, delta),
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
      expect(tester.getSize(find.byKey(_viewport)).width, 1400);
      expect(tester.getSize(find.byKey(const ValueKey('row-4'))).width, 825);
      await _wheel(tester, find.byKey(_viewport), -20);
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
      await _wheel(tester, find.byKey(_viewport), -20);
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
              body: Builder(
                builder: pageSurfaceExamples.examples.first.builder,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Topic'));
      await tester.pumpAndSettle();
      expect(find.text('Topic · 1'), findsOneWidget);
      await tester.tap(find.text('Limit content width'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
