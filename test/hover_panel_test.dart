import 'package:discourse_native/src/shell/hover_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an open panel follows an anchor moved by a rebuild', (
    tester,
  ) async {
    const anchorKey = Key('anchor');
    const panelKey = Key('panel');
    var top = 40.0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Stack(
                children: [
                  Positioned(
                    top: top,
                    left: 40,
                    child: HoverPanel(
                      child: SizedBox(
                        key: anchorKey,
                        width: 100 + top * 0,
                        height: 30,
                      ),
                      panelBuilder: (_) =>
                          const SizedBox(key: panelKey, width: 80, height: 40),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(anchorKey)));
    await tester.pump(HoverPanel.openDelay);
    await tester.pump();
    final before = tester.getTopLeft(find.byKey(panelKey));

    rebuild(() => top = 140);
    await tester.pump();
    await tester.pump();
    final after = tester.getTopLeft(find.byKey(panelKey));

    expect(after.dy - before.dy, closeTo(100, 0.01));
    await mouse.removePointer();
  });
}
