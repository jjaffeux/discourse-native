import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mobile in [false, true]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'drag handle supports drop and keyboard ($mobile, $direction)',
        (tester) async {
          var actions = 0;
          final drops = <int>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark.copyWith(
                platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
              ),
              home: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: Column(
                    children: [
                      DDragHandle<int>(
                        data: 7,
                        label: 'Move paragraph',
                        onPressed: () => actions++,
                      ),
                      const SizedBox(height: 60),
                      DDragRegion<int>(
                        accepts: (data) => data == 7,
                        onMove: (_, _) {},
                        onLeave: () {},
                        onDrop: (data, _) => drops.add(data),
                        child: const SizedBox(
                          width: 200,
                          height: 80,
                          child: DCard(child: Text('Destination')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(actions, 1);
          if (mobile) {
            expect(
              tester.getSize(find.byType(DDragHandle<int>)).height,
              greaterThanOrEqualTo(48),
            );
          }
          final gesture = await tester.startGesture(
            tester.getCenter(find.byType(DDragHandle<int>)),
            kind: mobile ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
          );
          await gesture.moveBy(const Offset(0, 30));
          await tester.pump();
          await gesture.moveTo(tester.getCenter(find.text('Destination')));
          await tester.pumpAndSettle();
          expect(find.text('Move paragraph'), findsNothing);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(drops, [7]);
          expect(
            actions,
            1,
            reason: 'dragging does not also activate the menu',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('disabled handles do not start drags or activate', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DDragHandle<int>(
            data: 1,
            label: 'Move paragraph',
            enabled: false,
            onPressed: () => actions++,
            onDragStarted: () => actions++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DDragHandle<int>));
    await tester.drag(find.byType(DDragHandle<int>), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(actions, 0);
  });
}
