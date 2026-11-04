import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  for (final overflows in [false, true]) {
    testWidgets(
      overflows
          ? 'overflowing forum rail scrolls with a trackpad'
          : 'fitting forum rail stays still during a trackpad gesture',
      (tester) async {
        await pumpShell(
          tester,
          desktop,
          instances: [
            for (var i = 0; i < (overflows ? 24 : 2); i++)
              instance('forum$i.example', title: 'Forum $i'),
          ],
        );
        final scrollable = find.descendant(
          of: find.byType(InstanceRail),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, overflows ? greaterThan(0) : 0);
        final forum = find.byKey(
          ValueKey(
            'instance-rail-tooltip-https://forum${overflows ? 2 : 0}.example',
          ),
        );
        final initialTop = tester.getTopLeft(forum).dy;
        final point = tester.getCenter(scrollable);
        final trackpad = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await trackpad.panZoomStart(point);
        for (var step = 1; step <= 4; step++) {
          await trackpad.panZoomUpdate(point, pan: Offset(0, -step * 20.0));
          await tester.pump(const Duration(milliseconds: 16));
          if (!overflows) {
            expect(position.pixels, 0);
            expect(tester.getTopLeft(forum).dy, initialTop);
          }
        }
        if (overflows) {
          expect(position.pixels, greaterThan(0));
          expect(tester.getTopLeft(forum).dy, lessThan(initialTop));
        }
        await trackpad.panZoomEnd();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS}),
    );
  }
}
