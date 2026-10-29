import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/mobile_page_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = ValueKey('mobile-page-title');
const _viewport = ValueKey('named-page');

Widget _app({
  required Widget page,
  bool reduced = false,
  Object identity = 'page',
}) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: DPageHeaderHost(
      identity: identity,
      builder: (context, header, child) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MobilePageTitle(
                  header: header,
                  siteUrl: 'https://forum.example',
                ),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
      child: page,
    ),
  ),
);

Widget _page(
  ScrollController scroll, {
  String title = 'Community guidelines',
  Widget? heading,
}) => DPageSurface.headed(
  title: heading ?? Text(title),
  bodyBuilder: (_, geometry) => CustomScrollView(
    key: _viewport,
    controller: scroll,
    slivers: [
      SliverToBoxAdapter(child: geometry.spacer),
      SliverList.builder(
        itemCount: 100,
        itemBuilder: (_, index) =>
            SizedBox(height: 60, child: Text('Guideline $index')),
      ),
    ],
  ),
);

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'visible title returns only its owning page to top (reduced: $reduced)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final scroll = ScrollController();
        final retained = ScrollController(initialScrollOffset: 300);
        addTearDown(scroll.dispose);
        addTearDown(retained.dispose);
        await tester.pumpWidget(
          _app(
            reduced: reduced,
            page: Stack(
              children: [
                Offstage(
                  child: TickerMode(
                    enabled: false,
                    child: _page(retained, title: 'Background page'),
                  ),
                ),
                _page(scroll),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_title).hitTestable(), findsNothing);
        expect(
          find.semantics.byLabel('Back to the top of Community guidelines'),
          findsNothing,
        );
        final viewport = find.byKey(_viewport).last;
        await tester.drag(viewport, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(find.byKey(_title).hitTestable(), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(_title)),
          matchesSemantics(
            label: 'Back to the top of Community guidelines',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        final offset = scroll.offset;
        final backgroundOffset = retained.offset;
        expect(offset, greaterThan(100));
        await tester.tap(find.byKey(_title));
        await tester.pump();
        if (reduced) {
          expect(scroll.offset, 0);
        } else {
          expect(scroll.offset, greaterThan(0));
          await tester.pump(const Duration(milliseconds: 100));
          expect(scroll.offset, lessThan(offset));
          expect(scroll.offset, greaterThan(0));
        }
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        expect(retained.offset, backgroundOffset);
        expect(find.byKey(_title).hitTestable(), findsNothing);
        expect(
          find.semantics.byLabel('Back to the top of Community guidelines'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'bar fades with heading motion and excludes an embedded scroller',
    (tester) async {
      final scroll = ScrollController(initialScrollOffset: 300);
      final nested = ScrollController(initialScrollOffset: 100);
      addTearDown(scroll.dispose);
      addTearDown(nested.dispose);
      late DPageHeader header;
      await tester.pumpWidget(
        _app(
          page: DPageSurface.headed(
            title: const Text('Guidelines'),
            bodyBuilder: (context, geometry) {
              header = DPageHeaderScope.maybeOf(context)!;
              return CustomScrollView(
                key: _viewport,
                controller: scroll,
                slivers: [
                  SliverToBoxAdapter(child: geometry.spacer),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 200,
                      child: ListView(
                        key: const ValueKey('embedded'),
                        controller: nested,
                        children: const [SizedBox(height: 1000)],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 4000)),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 450));
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(_viewport)),
      );
      await drag.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveBy(const Offset(0, -8));
      await tester.pump(const Duration(milliseconds: 20));
      expect(header.value, inExclusiveRange(0, 1));
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(of: find.byKey(_title), matching: find.byType(Opacity))
            .first,
      );
      expect(opacity.opacity, header.value);
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_title).hitTestable(), findsOneWidget);
      nested.jumpTo(150);
      await tester.pump();
      final nestedOffset = nested.offset;
      await tester.tap(find.byKey(_title));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(nested.offset, nestedOffset);
    },
  );

  testWidgets('topic title waits for the compact heading to retract', (
    tester,
  ) async {
    final scroll = ScrollController(initialScrollOffset: 60);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _app(
        page: DPageSurface.scrollable(
          titleText: 'A community discussion',
          framed: false,
          hideHeaderOnScroll: true,
          initialCompactHeader: false,
          header: const SizedBox(
            height: 300,
            child: Text('Full topic heading'),
          ),
          compactHeader: const SizedBox(
            height: 80,
            child: Text('Compact topic heading'),
          ),
          bodyBuilder: (_, geometry) => CustomScrollView(
            key: _viewport,
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(child: geometry.spacer),
              const SliverToBoxAdapter(child: SizedBox(height: 5000)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.timedDragFrom(
      tester.getBottomLeft(find.byKey(_viewport)) + const Offset(100, -30),
      const Offset(0, -50),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(60));
    expect(find.byKey(_title).hitTestable(), findsNothing);
    expect(find.text('Compact topic heading'), findsNothing);
    await tester.dragFrom(
      tester.getBottomLeft(find.byKey(_viewport)) + const Offset(100, -30),
      const Offset(0, -500),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Compact topic heading'), findsOneWidget);
    expect(find.text('Compact topic heading').hitTestable(), findsNothing);
    expect(find.byKey(_title).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(_title));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(find.text('Full topic heading').hitTestable(), findsOneWidget);
    expect(find.byKey(_title).hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'graphical headings do not publish titles or schedule render loops',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(_app(page: _page(scroll)));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_viewport), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byKey(_title).hitTestable(), findsOneWidget);
      await tester.pumpWidget(
        _app(
          identity: 'graphical',
          page: _page(scroll, heading: const DAvatarFallback(child: Text('M'))),
        ),
      );
      expect(await tester.pumpAndSettle(), lessThan(10));
      expect(find.byKey(_title), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
