import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _list = ValueKey('refresh-content-list');
const _handle = ValueKey('refresh-content-handle');

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final page in [false, true]) {
      testWidgets('refresh content stays in the $platform sheet, page $page', (
        tester,
      ) async {
        final response = Completer<void>();
        var refreshes = 0;
        var dismissals = 0;
        final enabled = ValueNotifier(true);
        addTearDown(enabled.dispose);
        await _pump(
          tester,
          platform: platform,
          page: page,
          enabled: enabled,
          onRefresh: () {
            refreshes++;
            return response.future;
          },
          onDismiss: () => dismissals++,
        );
        final bounds = tester.getRect(find.byType(DSheetContent));
        await _pull(tester);
        expect(refreshes, 1);
        expect(dismissals, 0);
        expect(tester.getRect(find.byType(DSheetContent)), bounds);
        enabled.value = false;
        await tester.pump();
        await _pull(tester);
        expect(refreshes, 1);
        expect(dismissals, 0);
        response.complete();
        await tester.pumpAndSettle();
        await _pull(tester);
        await tester.pumpAndSettle();
        expect(dismissals, 0);
        await tester.drag(find.byKey(_handle), const Offset(0, 350));
        await tester.pumpAndSettle();
        expect(dismissals, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'nested refresh content scrolls without refreshing or dismissing',
    (tester) async {
      var refreshes = 0;
      var dismissals = 0;
      await _pump(
        tester,
        nested: true,
        onRefresh: () async => refreshes++,
        onDismiss: () => dismissals++,
      );
      await _pull(tester);
      await tester.pumpAndSettle();
      expect(refreshes, 0);
      expect(dismissals, 0);
      await tester.drag(find.byKey(_list), const Offset(0, -200));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(_list),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a cancelled content pull leaves handle dismissal available', (
    tester,
  ) async {
    var dismissals = 0;
    await _pump(tester, onRefresh: null, onDismiss: () => dismissals++);
    final pull = await tester.startGesture(tester.getCenter(find.byKey(_list)));
    await pull.moveBy(const Offset(0, 180));
    await tester.pump();
    await pull.cancel();
    await tester.pumpAndSettle();
    expect(dismissals, 0);
    await tester.drag(find.byKey(_handle), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(dismissals, 1);
  });

  testWidgets(
    'first wheel over refresh content scrolls instead of dismissing',
    (tester) async {
      var dismissals = 0;
      await _pump(
        tester,
        count: 30,
        onRefresh: null,
        onDismiss: () => dismissals++,
      );
      final point = tester.getCenter(find.byKey(_list));
      final bounds = tester.getRect(find.byType(DSheetContent));
      for (final dy in [-180.0, 180.0]) {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: point, scrollDelta: Offset(0, dy)),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.getRect(find.byType(DSheetContent)), bounds);
      }
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(_list),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(position.pixels, greaterThan(0));
      expect(dismissals, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'trackpad content pull refreshes while the page sheet stays put',
    (tester) async {
      var refreshes = 0;
      var dismissals = 0;
      await _pump(
        tester,
        platform: TargetPlatform.macOS,
        onRefresh: () async => refreshes++,
        onDismiss: () => dismissals++,
      );
      final point = tester.getCenter(find.byKey(_list));
      final bounds = tester.getRect(find.byType(DSheetContent));
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(point);
      for (var step = 1; step <= 40; step++) {
        await trackpad.panZoomUpdate(point, pan: Offset(0, step * 30.0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getRect(find.byType(DSheetContent)), bounds);
      }
      expect(dismissals, 0);
      expect(find.bySemanticsLabel('Release to refresh'), findsOneWidget);
      await trackpad.panZoomEnd();
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(dismissals, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  bool page = true,
  bool nested = false,
  int count = 1,
  ValueNotifier<bool>? enabled,
  required Future<void> Function()? onRefresh,
  required VoidCallback onDismiss,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Widget content() {
    final list = ListView(
      key: _list,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < (nested ? 30 : count); i++)
          SizedBox(height: 60, child: Text('Row $i')),
      ],
    );
    final scroll = nested
        ? ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [SizedBox(height: 500, child: list)],
          )
        : list;
    return DPullToRefresh(
      onRefresh: enabled?.value == false ? null : onRefresh,
      child: Column(
        children: [
          const DSheetDragRegion(
            child: Padding(
              key: _handle,
              padding: EdgeInsets.all(16),
              child: Text('Dismiss sheet'),
            ),
          ),
          Expanded(child: scroll),
        ],
      ),
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: DSheetViewport(
          onDismiss: onDismiss,
          content: DSheetContent(
            side: DSheetSide.bottom,
            variant: page ? DSheetVariant.page : DSheetVariant.standard,
            showCloseButton: false,
            fillAvailableHeight: true,
            scrollWholeSheet: false,
            children: [
              Expanded(
                child: enabled == null
                    ? content()
                    : ValueListenableBuilder(
                        valueListenable: enabled,
                        builder: (_, _, _) => content(),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pull(WidgetTester tester) async {
  final bounds = tester.getRect(find.byType(DSheetContent));
  final pull = await tester.startGesture(tester.getCenter(find.byKey(_list)));
  await pull.moveBy(const Offset(0, 20));
  await pull.moveBy(const Offset(0, 330));
  await tester.pump();
  expect(tester.getRect(find.byType(DSheetContent)), bounds);
  await pull.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
