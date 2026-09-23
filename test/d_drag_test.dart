import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final enabled in [false, true]) {
    testWidgets(
      'long-press region preserves child gestures when enabled=$enabled',
      (tester) async {
        var taps = 0;
        var childHolds = 0;
        var starts = 0;
        var moves = 0;
        var drops = 0;
        var ends = 0;
        var eligible = true;
        await tester.pumpWidget(
          MaterialApp(
            home: DLongPressDragRegion<int>(
              enabled: enabled,
              dataAt: (_) => eligible ? 7 : null,
              onStart: (data) {
                starts++;
                return true;
              },
              onMove: (_, _) => moves++,
              onDrop: (_, _) => drops++,
              onEnd: () => ends++,
              child: GestureDetector(
                onTap: () => taps++,
                onLongPress: () => childHolds++,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.tapAt(const Offset(100, 100));
        expect(taps, 1);
        final gesture = await tester.startGesture(const Offset(100, 100));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.moveBy(const Offset(0, 100));
        await gesture.up();
        expect(starts, enabled ? 1 : 0);
        expect(moves, enabled ? greaterThan(0) : 0);
        expect(drops, enabled ? 1 : 0);
        expect(ends, enabled ? 1 : 0);
        expect(childHolds, enabled ? 0 : 1);
        eligible = false;
        await tester.longPressAt(const Offset(100, 100));
        expect(childHolds, enabled ? 1 : 2);
        expect(starts, enabled ? 1 : 0);
      },
    );
  }

  for (final (removeSource, cancel) in [
    (false, false),
    (true, false),
    (false, true),
    (true, true),
  ]) {
    testWidgets(
      'drag cursor stays a fist between frames ($removeSource, $cancel)',
      (tester) async {
        var actions = 0;
        var ended = 0;
        var showHandle = true;
        late StateSetter rebuild;
        final drops = <int>[];
        final cursorUpdates = <String>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.mouseCursor, (
          call,
        ) async {
          if (call.method == 'activateSystemCursor') {
            cursorUpdates.add((call.arguments as Map)['kind'] as String);
          }
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            SystemChannels.mouseCursor,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return Column(
                    children: [
                      if (showHandle)
                        DDragHandle<int>(
                          data: 7,
                          label: 'Move paragraph',
                          onPressed: () => actions++,
                          onDragEnd: () => ended++,
                        )
                      else
                        const SizedBox(height: 28),
                      const SizedBox(height: 60),
                      DDragRegion<int>(
                        accepts: (data) => data == 7,
                        onMove: (_, _) {},
                        onLeave: () {},
                        onDrop: (data, _) => drops.add(data),
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.text,
                          child: SizedBox(
                            width: 200,
                            height: 80,
                            child: Text('Destination'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        final handle = find.byType(DDragHandle<int>);
        final point = tester.getCenter(handle);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: point);
        await tester.pump();
        MouseCursor? cursor() =>
            tester.binding.mouseTracker.debugDeviceActiveCursor(1);
        expect(cursor(), SystemMouseCursors.grab);
        await mouse.down(point);
        await tester.pump();
        expect(cursor(), SystemMouseCursors.grabbing);
        await mouse.up();
        await tester.pump();
        expect(actions, 1);
        expect(cursor(), SystemMouseCursors.grab);

        await mouse.down(point);
        await mouse.moveBy(const Offset(0, 30));
        await tester.pump();
        expect(cursorUpdates.last, 'grabbing');
        cursorUpdates.clear();
        if (removeSource) {
          rebuild(() => showHandle = false);
          await tester.pump();
        }
        final destination = tester.getCenter(find.text('Destination'));
        for (final position in [
          destination,
          const Offset(400, 300),
          const Offset(10, 400),
          destination + const Offset(10, 0),
          destination,
        ]) {
          await mouse.moveTo(position);
          expect(
            cursor(),
            SystemMouseCursors.grabbing,
            reason: 'pointer events must retain the fist before the next frame',
          );
          await tester.pump();
          expect(cursor(), SystemMouseCursors.grabbing);
        }
        expect(cursorUpdates, everyElement('grabbing'));
        if (cancel) {
          await mouse.cancel();
        } else {
          await mouse.up();
        }
        await tester.pump();
        expect(cursor(), SystemMouseCursors.text);
        expect(cursorUpdates.last, 'text');
        expect(drops, cancel ? isEmpty : [7]);
        expect(ended, 1);
        expect(actions, 1);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }

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
