import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editor canvas focuses within its visible bounds', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DInputFocusRegion(
              focusNode: focus,
              child: ColoredBox(
                key: const ValueKey('canvas'),
                color: Colors.white,
                child: SizedBox(
                  width: 240,
                  height: 160,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: DInput(focusNode: focus, hintText: 'Message'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byKey(const ValueKey('canvas')));
    expect(focus.hasFocus, isFalse);
    await tester.tapAt(bounds.bottomLeft + const Offset(24, -16));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    focus.unfocus();
    await tester.pump();
    await tester.tapAt(bounds.bottomRight + const Offset(16, 16));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(focus.canRequestFocus, isTrue);
  });

  testWidgets(
    'nested actions keep their activation and disabled canvas cannot focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var pressed = 0;
      Future<void> show(bool enabled) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DInputFocusRegion(
                enabled: enabled,
                focusNode: focus,
                child: SizedBox(
                  width: 240,
                  height: 160,
                  child: Column(
                    children: [
                      DInput(focusNode: focus),
                      DButton(
                        label: const Text('Attach'),
                        onPressed: () => pressed++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await show(true);
      await tester.tap(find.text('Attach'));
      await tester.pump();
      expect(pressed, 1);
      expect(focus.hasFocus, isFalse);
      await show(false);
      final bounds = tester.getRect(find.byType(DInputFocusRegion));
      await tester.tapAt(bounds.bottomLeft + const Offset(24, -8));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
