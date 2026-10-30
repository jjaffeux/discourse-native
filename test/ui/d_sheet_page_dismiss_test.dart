import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _sheet = find.byType(DSheetContent);
final _reader = find.byType(ListView);
final _header = find.text('Topic header');
final _handle = find.byKey(const ValueKey('sheet-drag-handle'));

Future<void> _pumpPage(
  WidgetTester tester,
  TargetPlatform platform,
  ScrollController scroll, {
  bool hasMoreBefore = false,
  bool loadingBefore = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var visible = true;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: StatefulBuilder(
        builder: (context, setState) => DSheetDragScope(
          child: Column(
            children: [
              const DSheetDragRegion(
                child: SizedBox(
                  height: 60,
                  child: Center(child: Text('Topic header')),
                ),
              ),
              Expanded(
                child: visible
                    ? DSheetViewport(
                        onDismiss: () => setState(() => visible = false),
                        content: DSheetContent(
                          side: DSheetSide.bottom,
                          variant: DSheetVariant.page,
                          showCloseButton: false,
                          children: [
                            Expanded(
                              child: DScrollChromePagination(
                                hasMore: false,
                                loading: false,
                                hasMoreBefore: hasMoreBefore,
                                loadingBefore: loadingBefore,
                                child: ListView.builder(
                                  controller: scroll,
                                  itemCount: 50,
                                  itemBuilder: (_, index) => SizedBox(
                                    height: 48,
                                    child: Text('Post $index'),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final loading in [false, true]) {
      for (final input in ['touch', 'trackpad', 'wheel']) {
        testWidgets(
          '$input at a temporary top stays in the reader on $platform (loading: $loading)',
          (tester) async {
            final scroll = ScrollController();
            addTearDown(scroll.dispose);
            await _pumpPage(
              tester,
              platform,
              scroll,
              hasMoreBefore: !loading,
              loadingBefore: loading,
            );
            final bounds = tester.getRect(_sheet);
            final point = tester.getCenter(_reader);
            if (input == 'wheel') {
              for (var step = 0; step < 4; step++) {
                await tester.sendEventToBinding(
                  PointerScrollEvent(
                    position: point,
                    scrollDelta: const Offset(0, -60),
                  ),
                );
                await tester.pump(const Duration(milliseconds: 20));
              }
            } else if (input == 'trackpad') {
              final pan = await tester.createGesture(
                kind: PointerDeviceKind.trackpad,
              );
              await pan.panZoomStart(point);
              await pan.moveBy(const Offset(0, 30));
              await pan.moveBy(const Offset(0, 220));
              await pan.up();
            } else {
              await tester.drag(_reader, const Offset(0, 250));
            }
            await tester.pumpAndSettle();
            expect(tester.getRect(_sheet), bounds);

            await tester.drag(
              loading ? _header : _handle,
              const Offset(0, 220),
            );
            await tester.pumpAndSettle();
            expect(_sheet, findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
    testWidgets('reaching the top requires a fresh page pull on $platform', (
      tester,
    ) async {
      final scroll = ScrollController(initialScrollOffset: 100);
      addTearDown(scroll.dispose);
      await _pumpPage(tester, platform, scroll);
      final bounds = tester.getRect(_sheet);
      final drag = await tester.startGesture(
        tester.getTopLeft(_reader) + const Offset(100, 100),
      );
      await drag.moveBy(const Offset(0, 30));
      await drag.moveBy(const Offset(0, 200));
      await drag.moveBy(const Offset(0, 180));
      await tester.pump();
      expect(scroll.offset, lessThanOrEqualTo(0));
      expect(tester.getRect(_sheet), bounds);
      await drag.up();
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(scroll.offset, closeTo(0, .01));

      await tester.drag(_reader, const Offset(0, 220));
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolling away and back cannot dismiss a page on $platform', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await _pumpPage(tester, platform, scroll);
      final bounds = tester.getRect(_sheet);
      final drag = await tester.startGesture(tester.getCenter(_reader));
      await drag.moveBy(const Offset(0, -30));
      await drag.moveBy(const Offset(0, -100));
      await tester.pump();
      expect(scroll.offset, greaterThan(0));
      await drag.moveBy(const Offset(0, 150));
      await drag.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(tester.getRect(_sheet), bounds);
      await drag.up();
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
    });

    testWidgets('trackpad scrolling requires a fresh page pull on $platform', (
      tester,
    ) async {
      final scroll = ScrollController(initialScrollOffset: 100);
      addTearDown(scroll.dispose);
      await _pumpPage(tester, platform, scroll);
      final bounds = tester.getRect(_sheet);
      final point = tester.getCenter(_reader);
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pan.panZoomStart(point);
      await pan.moveBy(const Offset(0, 30));
      await pan.moveBy(const Offset(0, 200));
      await pan.moveBy(const Offset(0, 180));
      await tester.pump();
      expect(tester.getRect(_sheet), bounds);
      await pan.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(0, .01));

      await pan.panZoomStart(point);
      await pan.moveBy(const Offset(0, 30));
      await pan.moveBy(const Offset(0, 200));
      await pan.up();
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final origin in ['reader', 'header', 'handle']) {
      testWidgets(
        '$origin page dismissal requires distance even at speed on $platform',
        (tester) async {
          final scroll = ScrollController(
            initialScrollOffset: origin == 'reader' ? 0 : 400,
          );
          addTearDown(scroll.dispose);
          await _pumpPage(tester, platform, scroll);
          final target = switch (origin) {
            'reader' => _reader,
            'header' => _header,
            _ => _handle,
          };
          final bounds = tester.getRect(_sheet);
          await tester.fling(target, const Offset(0, 70), 1800);
          await tester.pumpAndSettle();
          expect(_sheet, findsOneWidget);
          expect(tester.getRect(_sheet), bounds);

          final drag = await tester.startGesture(tester.getCenter(target));
          await drag.moveBy(const Offset(0, 30));
          await drag.moveBy(const Offset(0, 150));
          await tester.pump();
          expect(tester.getRect(_sheet).top, greaterThan(bounds.top));
          await drag.cancel();
          await tester.pumpAndSettle();
          expect(tester.getRect(_sheet), bounds);

          await tester.drag(target, const Offset(0, 220));
          await tester.pumpAndSettle();
          expect(_sheet, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
