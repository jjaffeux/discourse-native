import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'image_grid_test.dart' as fixture;

void main() {
  testWidgets('scrolling a photo mosaic retains already painted thumbnails', (
    tester,
  ) async {
    final requests = <Uri>[];
    await fixture.pumpHydrationGrid(
      tester,
      fixture.grid(14, width: 375, height: 499),
      requests,
      wrap: (grid) => Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 390, child: RepaintBoundary(child: grid)),
      ),
    );
    for (var frame = 0; frame < 30; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final first = find.descendant(
      of: fixture.gridImage('img0-t.png'),
      matching: find.byType(RawImage),
    );
    expect(first, findsOneWidget);
    expect(tester.widget<RawImage>(first).image, isNotNull);
    final photo = tester.renderObject<RenderImage>(first);
    final before = tester.getRect(first);
    final requestsBefore = requests.length;
    final decodedBefore = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((image) => image.image != null)
        .length;
    var paints = 0;
    final previous = debugOnProfilePaint;
    debugOnProfilePaint = (object) {
      previous?.call(object);
      if (identical(object, photo)) paints++;
    };
    try {
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      scroll.pointerScroll(200);
      for (var frame = 0; frame < 10; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(requests.length, greaterThan(requestsBefore));
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .where((image) => image.image != null)
            .length,
        greaterThan(decodedBefore),
      );
      expect(tester.renderObject(first), same(photo));
      expect(tester.getRect(first), before.shift(const Offset(0, -200)));
      expect(paints, 0);
      expect(tester.takeException(), isNull);
    } finally {
      debugOnProfilePaint = previous;
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
