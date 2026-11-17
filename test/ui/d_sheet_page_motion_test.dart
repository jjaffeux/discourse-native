import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _underlay = ValueKey('previous-page');
const _previousFill = Color(0xffe0e0e0);
const _sheetFill = Color(0xff4060c0);
const _redMarker = ValueKey('source-red-marker');
const _blueMarker = ValueKey('source-blue-marker');
final _sheet = find.byType(DSheetContent);
final _handle = find.byKey(const ValueKey('sheet-drag-handle'));

Finder _backgroundOf(WidgetTester tester) => find.byWidget(
  tester.widget<DSheetViewport>(find.byType(DSheetViewport)).underlay!,
);

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

Future<void> _expectSynchronizedEntrance(WidgetTester tester) async {
  double width() => _paintedRect(tester, find.byKey(_underlay)).width;
  double top() => tester.getTopLeft(_sheet).dy;
  final startWidth = width();
  final startTop = top();
  final frames = <(double, double)>[];
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    frames.add((top(), width()));
  }
  await tester.pumpAndSettle();
  final travel = startTop - top();
  final shrink = startWidth - width();
  expect(travel, greaterThan(0), reason: 'The sheet moves into position');
  expect(shrink, greaterThan(0), reason: 'The page recedes behind the sheet');
  for (final (index, (sheetTop, pageWidth)) in frames.indexed) {
    final sheetProgress = (startTop - sheetTop) / travel;
    final pageProgress = (startWidth - pageWidth) / shrink;
    expect(
      sheetProgress,
      closeTo(pageProgress, .01),
      reason: 'Sheet travel and page scale after ${(index + 1) * 80} ms',
    );
  }
}

Future<Color> _pixel(WidgetTester tester, Offset point) async =>
    (await tester.runAsync(() async {
      final builder = ui.SceneBuilder();
      tester.binding.renderViews.first.debugLayer!.addToScene(builder);
      final scene = builder.build();
      final image = await scene.toImage(400, 600);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final index = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
      final color = Color.fromARGB(
        bytes!.getUint8(index + 3),
        bytes.getUint8(index),
        bytes.getUint8(index + 1),
        bytes.getUint8(index + 2),
      );
      image.dispose();
      scene.dispose();
      return color;
    }))!;

Future<_PageHarnessState> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.iOS,
  bool reducedMotion = false,
  bool history = false,
  Color sheetFill = _sheetFill,
  bool framed = false,
  bool liveUnderlay = false,
}) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<_PageHarnessState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: _PageHarness(
        key: key,
        reducedMotion: reducedMotion,
        history: history,
        sheetFill: sheetFill,
        framed: framed,
        liveUnderlay: liveUnderlay,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

void main() {
  for (final variant in [
    DSheetVariant.standard,
    DSheetVariant.menu,
    DSheetVariant.adaptiveMenu,
  ]) {
    testWidgets('a phone $variant slides over a stationary background', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = DSheetController<void>();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: ColoredBox(
            key: _underlay,
            color: _previousFill,
            child: Center(
              child: DSheet<void>(
                controller: controller,
                trigger: DSheetTrigger(
                  builder: (context, open) =>
                      DButton(onPressed: open, label: const Text('Open sheet')),
                ),
                content: DSheetContent(
                  side: DSheetSide.bottom,
                  variant: variant,
                  children: const [
                    DSheetBody(
                      child: SizedBox(height: 200, child: Text('Sheet body')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Rect background() => _paintedRect(tester, find.byKey(_underlay));
      final initialBackground = background();

      await tester.tap(find.text('Open sheet'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(background(), initialBackground);
      expect(tester.getTopLeft(_sheet).dy, closeTo(600, .01));
      await tester.pump(const Duration(milliseconds: 160));
      final openingTop = tester.getTopLeft(_sheet).dy;
      expect(openingTop, lessThan(600));
      expect(background(), initialBackground);
      await tester.pumpAndSettle();
      final openTop = tester.getTopLeft(_sheet).dy;
      expect(openTop, lessThan(openingTop));
      expect(background(), initialBackground);
      final drag = await tester.startGesture(tester.getCenter(_handle));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 48));
      await tester.pump();
      expect(tester.getTopLeft(_sheet).dy, greaterThan(openTop));
      expect(background(), initialBackground);
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_sheet).dy, closeTo(openTop, .01));
      expect(background(), initialBackground);

      controller.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getTopLeft(_sheet).dy, greaterThan(openTop));
      expect(background(), initialBackground);
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(background(), initialBackground);
    });
  }

  for (final variant in [DSheetVariant.menu, DSheetVariant.adaptiveMenu]) {
    testWidgets('a retained phone $variant enters as its background recedes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final open = ValueNotifier(false);
      addTearDown(open.dispose);
      final covering = ValueNotifier(false);
      addTearDown(covering.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: DSheetDragScope(
            child: ValueListenableBuilder(
              valueListenable: open,
              builder: (context, open, _) => Stack(
                fit: StackFit.expand,
                children: [
                  DSheetBackdrop(
                    covered: open,
                    child: const ColoredBox(
                      key: _underlay,
                      color: _previousFill,
                    ),
                  ),
                  if (open)
                    DSheetViewport(
                      covering: covering,
                      content: DSheetContent(
                        side: DSheetSide.bottom,
                        variant: variant,
                        fillAvailableHeight: variant == DSheetVariant.menu,
                        showCloseButton: false,
                        children: const [
                          DSheetBody(
                            child: SizedBox(
                              height: 200,
                              child: Text('Sheet body'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      open.value = true;
      await tester.pump();
      await tester.pump();
      expect(covering.value, isFalse);
      await _expectSynchronizedEntrance(tester);
      if (variant == DSheetVariant.menu) {
        expect(covering.value, isTrue);
      }
      open.value = false;
      await tester.pumpAndSettle();
      expect(covering.value, isFalse);
    });
  }

  for (final headerHeight in [28.0, 92.0]) {
    testWidgets('a captured page keeps its origin when the frame moves to '
        '$headerHeight', (tester) async {
      final state = await _pump(tester, history: true, framed: true);
      final source = _paintedRect(tester, find.byKey(_underlay));
      final marker = tester.getRect(find.byKey(_blueMarker));
      state.visit(1, headerHeight: headerHeight);
      await tester.pumpAndSettle();
      Future<void> expectMarkerAligned() async {
        final background = _paintedRect(tester, _backgroundOf(tester));
        final scale = background.width / source.width;
        final color = await _pixel(
          tester,
          background.topLeft +
              (marker.center - source.topLeft - Offset(0, headerHeight - 60)) *
                  scale,
        );
        expect(
          color.b,
          greaterThan(color.r + .5),
          reason: 'The saved marker stays at its original page position',
        );
      }

      final cancelled = await tester.startGesture(tester.getCenter(_handle));
      await cancelled.moveBy(const Offset(0, 20));
      await cancelled.moveBy(const Offset(0, 90));
      await tester.pump();
      await expectMarkerAligned();
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(state.entry, 1);

      final drag = await tester.startGesture(tester.getCenter(_handle));
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 220));
      await tester.pump();
      await expectMarkerAligned();
      await drag.up();
      await tester.pumpAndSettle();
      expect(state.entry, 0);
      expect(tester.getRect(find.byKey(_blueMarker)), marker);
      expect(tester.takeException(), isNull);
    });
  }

  for (final live in [false, true]) {
    testWidgets(
      'the whole ${live ? 'live' : 'captured'} page scales together',
      (tester) async {
        final state = await _pump(
          tester,
          history: true,
          framed: true,
          liveUnderlay: live,
        );
        final source = _paintedRect(tester, find.byKey(_underlay));
        final red = tester.getRect(find.byKey(_redMarker));
        final blue = tester.getRect(find.byKey(_blueMarker));
        Future<void> expectContentAligned() async {
          final background = _paintedRect(tester, _backgroundOf(tester));
          final scale = background.width / source.width;
          final redPixel = await _pixel(
            tester,
            background.topLeft + (red.center - source.topLeft) * scale,
          );
          final bluePixel = await _pixel(
            tester,
            background.topLeft + (blue.center - source.topLeft) * scale,
          );
          expect(
            redPixel.r,
            greaterThan(redPixel.g + .5),
            reason: 'The red marker scales with its container',
          );
          expect(
            bluePixel.b,
            greaterThan(bluePixel.r + .5),
            reason: 'The blue marker scales with its container',
          );
        }

        state.visit(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 140));
        await expectContentAligned();
        await tester.pumpAndSettle();
        for (final keyboard in [0.0, 260.0]) {
          state.keyboard(keyboard);
          await tester.pumpAndSettle();
          final pull = await tester.startGesture(tester.getCenter(_handle));
          await pull.moveBy(const Offset(0, 20));
          await pull.moveBy(const Offset(0, 70));
          await tester.pump();
          await expectContentAligned();
          await pull.moveBy(const Offset(0, 90));
          await tester.pump();
          await expectContentAligned();
          await pull.cancel();
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a page slides up opaque while its inert underlay recedes', (
    tester,
  ) async {
    final state = await _pump(
      tester,
      sheetFill: _sheetFill.withValues(alpha: .6),
    );
    final semantics = tester.ensureSemantics();
    state.visit(1);
    await tester.pump();
    expect(tester.getTopLeft(_sheet).dy, 600);
    expect(_paintedRect(tester, _backgroundOf(tester)).width, 400);
    expect(find.bySemanticsLabel('Previous action'), findsNothing);
    expect(find.text('Previous action').hitTestable(), findsNothing);

    await tester.pump(const Duration(milliseconds: 70));
    final openingTop = tester.getTopLeft(_sheet).dy;
    expect(openingTop, inExclusiveRange(0, 600));
    final backgroundBounds = _paintedRect(tester, _backgroundOf(tester));
    expect(backgroundBounds.width, lessThan(400));
    expect(
      await _pixel(tester, backgroundBounds.topLeft + const Offset(2, 2)),
      Colors.black,
    );
    expect(
      (await _pixel(tester, const Offset(200, 50))).r,
      lessThan(_previousFill.r),
    );
    expect(await _pixel(tester, const Offset(300, 580)), _sheetFill);

    state.rebuild();
    await tester.pump();
    expect(tester.getTopLeft(_sheet).dy, openingTop);
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getTopLeft(_sheet).dy, lessThan(openingTop));
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getTopLeft(_sheet).dy, greaterThan(0));
    expect(
      _paintedRect(tester, _backgroundOf(tester)).width,
      inExclusiveRange(376.0, backgroundBounds.width),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_sheet).dy, 0);
    expect(
      tester
          .widget<Material>(
            find.descendant(of: _sheet, matching: find.byType(Material)).first,
          )
          .color,
      _sheetFill.withValues(alpha: .6),
    );
    expect(_backgroundOf(tester), findsNothing);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  for (final (platform, history) in [
    (TargetPlatform.iOS, false),
    (TargetPlatform.iOS, true),
    (TargetPlatform.android, false),
    (TargetPlatform.android, true),
  ]) {
    testWidgets(
      'pulling down restores a rounded background on $platform (snapshot: $history)',
      (tester) async {
        final state = await _pump(tester, platform: platform, history: history);
        state.visit(1);
        await tester.pumpAndSettle();
        final drag = await tester.startGesture(tester.getCenter(_handle));
        await drag.moveBy(const Offset(0, 20));
        await drag.moveBy(const Offset(0, 70));
        await tester.pump();
        final backgroundBounds = _paintedRect(tester, _backgroundOf(tester));
        final firstWidth = backgroundBounds.width;
        expect(
          await _pixel(tester, backgroundBounds.topLeft + const Offset(2, 2)),
          Colors.black,
        );
        expect(
          await _pixel(tester, backgroundBounds.topRight + const Offset(-3, 2)),
          Colors.black,
        );
        final firstColor = await _pixel(tester, const Offset(200, 50));
        expect(firstWidth, lessThan(400));
        expect(firstColor.r, lessThan(_previousFill.r));

        await drag.moveBy(const Offset(0, 90));
        await tester.pump();
        expect(
          _paintedRect(tester, _backgroundOf(tester)).width,
          greaterThan(firstWidth),
        );
        expect(
          (await _pixel(tester, const Offset(200, 50))).r,
          greaterThan(firstColor.r),
        );
        await drag.cancel();
        await tester.pumpAndSettle();
        expect(state.entry, 1);
        expect(tester.getTopLeft(_sheet).dy, 0);
        expect(_backgroundOf(tester), findsNothing);

        await tester.drag(_handle, const Offset(0, 200));
        await tester.pump();
        expect(state.entry, 1);
        await tester.pumpAndSettle();
        expect(state.entry, 0);
        expect(_sheet, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('reduced motion skips entrance and depth, including mid-flight', (
    tester,
  ) async {
    final state = await _pump(tester, reducedMotion: true);
    state.visit(1);
    await tester.pump();
    expect(tester.getTopLeft(_sheet).dy, 0);
    final drag = await tester.startGesture(tester.getCenter(_handle));
    await drag.moveBy(const Offset(0, 20));
    await drag.moveBy(const Offset(0, 90));
    await tester.pump();
    expect(
      _paintedRect(tester, _backgroundOf(tester)),
      const Rect.fromLTWH(0, 0, 400, 600),
    );
    expect(await _pixel(tester, const Offset(200, 50)), _previousFill);
    await drag.cancel();
    await tester.pumpAndSettle();

    state.setReducedMotion(false);
    state.visit(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getTopLeft(_sheet).dy, greaterThan(0));
    state.setReducedMotion(true);
    await tester.pump();
    expect(tester.getTopLeft(_sheet).dy, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('history returns and completed swipes do not replay entrance', (
    tester,
  ) async {
    final state = await _pump(tester, history: true);
    state.visit(1);
    await tester.pump();
    expect(tester.getTopLeft(_sheet).dy, 600);
    await tester.pumpAndSettle();
    state.visit(2);
    await tester.pump();
    expect(tester.getTopLeft(_sheet).dy, 600);
    await tester.pumpAndSettle();
    await tester.drag(_handle, const Offset(0, 200));
    for (var frame = 0; frame < 30 && state.entry == 2; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(state.entry, 1);
    expect(tester.getTopLeft(_sheet).dy, 0);
    await tester.pumpAndSettle();

    final edge = await tester.startGesture(const Offset(395, 250));
    await edge.moveBy(const Offset(-160, 0));
    await edge.up();
    for (var frame = 0; frame < 30 && state.entry == 1; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(state.entry, 2);
    expect(tester.getTopLeft(_sheet).dy, 0);
    await tester.pumpAndSettle();
    state.switchTab();
    await tester.pump();
    expect(tester.getTopLeft(_sheet).dy, 0);
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getTopLeft(_sheet).dy, 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _PageHarness extends StatefulWidget {
  const _PageHarness({
    super.key,
    required this.reducedMotion,
    required this.history,
    required this.sheetFill,
    required this.framed,
    required this.liveUnderlay,
  });

  final bool reducedMotion;
  final bool history;
  final Color sheetFill;
  final bool framed;
  final bool liveUnderlay;

  @override
  State<_PageHarness> createState() => _PageHarnessState();
}

class _PageHarnessState extends State<_PageHarness> {
  int entry = 0;
  int tab = 0;
  double keyboardBottom = 0;
  double headerHeight = 60;
  late bool reducedMotion = widget.reducedMotion;

  void visit(int value, {double? headerHeight}) => setState(() {
    entry = value;
    if (headerHeight != null) this.headerHeight = headerHeight;
  });
  void rebuild() => setState(() {});
  void setReducedMotion(bool value) => setState(() => reducedMotion = value);
  void switchTab() => setState(() => tab++);
  void keyboard(double value) => setState(() => keyboardBottom = value);

  Widget get previous => DPageSurface(
    key: _underlay,
    borderRadius: BorderRadius.zero,
    backgroundColor: _previousFill,
    child: Stack(
      children: [
        Center(
          child: DButton(
            label: const Text('Previous action'),
            onPressed: () {},
          ),
        ),
        const Positioned(
          left: 31,
          top: 12,
          width: 100,
          height: 6,
          child: ColoredBox(key: _redMarker, color: Colors.red),
        ),
        const Positioned(
          left: 31,
          top: 56,
          width: 80,
          height: 6,
          child: ColoredBox(key: _blueMarker, color: Colors.blue),
        ),
      ],
    ),
  );

  Widget page(BuildContext context) => entry == 0
      ? previous
      : DSheetViewport(
          key: ValueKey((tab, entry)),
          onDismiss: () => visit(entry - 1),
          underlay: widget.history && !widget.liveUnderlay
              ? DHistoryTransition.previousPageUnderlayOf(context)
              : previous,
          content: DSheetContent(
            side: DSheetSide.bottom,
            variant: DSheetVariant.page,
            showCloseButton: false,
            backgroundColor: widget.sheetFill,
            children: [Expanded(child: Center(child: Text('Reader $entry')))],
          ),
        );

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reducedMotion,
      viewInsets: EdgeInsets.only(bottom: keyboardBottom),
    ),
    child: ColoredBox(
      color: Colors.black,
      child: widget.history
          ? DHistoryTransition(
              history: tab,
              tab: (id: tab, index: tab),
              tabOwner: 'account',
              frameBuilder: widget.framed
                  ? (context, page) => Padding(
                      padding: EdgeInsets.only(bottom: keyboardBottom),
                      child: Column(
                        children: [
                          SizedBox(
                            height: entry == 0 ? 60 : headerHeight,
                            child: const Text('Stationary header'),
                          ),
                          Expanded(child: page),
                        ],
                      ),
                    )
                  : null,
              entry: entry,
              previousEntry: entry > 0 ? entry - 1 : null,
              nextEntry: entry < 2 ? entry + 1 : null,
              onBack: entry > 0 ? () => visit(entry - 1) : null,
              onForward: entry < 2 ? () => visit(entry + 1) : null,
              child: widget.framed
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Builder(builder: page),
                    )
                  : Builder(builder: page),
            )
          : Builder(builder: page),
    ),
  );
}
