import 'package:discourse_native/src/foundation/active_use.dart';
import 'package:discourse_native/src/foundation/active_use_signals.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var now = DateTime.utc(2026, 11, 9, 12);
  ActiveUse activeUse({bool foreground = true}) =>
      ActiveUse(foreground: foreground, clock: () => now);
  void advance(Duration by) => now = now.add(by);

  group('ActiveUse', () {
    test('holds for a minute after the app starts in front', () {
      final use = activeUse();
      advance(const Duration(seconds: 59));
      expect(use.isActive, isTrue);
      advance(const Duration(seconds: 1));
      expect(use.isActive, isFalse);
    });

    test('input renews the minute', () {
      final use = activeUse();
      advance(const Duration(seconds: 59));
      use.seen();
      advance(const Duration(seconds: 59));
      expect(use.isActive, isTrue);
    });

    test('the background ends it at once, whatever the last input', () {
      final use = activeUse();
      use.seen();
      use.setForeground(false);
      expect(use.isActive, isFalse);
    });

    test('an app started behind other windows is not in use', () {
      expect(activeUse(foreground: false).isActive, isFalse);
    });

    test('coming back counts as being seen', () {
      final use = activeUse();
      use.setForeground(false);
      advance(const Duration(hours: 1));
      use.setForeground(true);
      expect(use.isActive, isTrue);
    });

    test('staying in front does not count as being seen', () {
      final use = activeUse();
      advance(const Duration(minutes: 1));
      use.setForeground(true);
      expect(use.isActive, isFalse);
    });
  });

  group('ActiveUseSignals', () {
    late ActiveUse use;
    late ActiveUseSignals signals;
    var attached = false;

    Future<void> pumpIdle(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      use = activeUse();
      signals = ActiveUseSignals(use)..attach();
      attached = true;
      advance(const Duration(minutes: 1));
      expect(use.isActive, isFalse);
    }

    tearDown(() {
      if (attached) signals.detach();
    });

    testWidgets('a touch is input', (tester) async {
      await pumpIdle(tester);
      final gesture = await tester.startGesture(const Offset(10, 10));
      expect(use.isActive, isTrue);
      await gesture.up();
    });

    testWidgets('dragging keeps counting as input', (tester) async {
      await pumpIdle(tester);
      final gesture = await tester.startGesture(const Offset(10, 10));
      advance(const Duration(minutes: 1));
      expect(use.isActive, isFalse);
      await gesture.moveBy(const Offset(0, 30));
      expect(use.isActive, isTrue);
      await gesture.up();
    });

    testWidgets('a mouse wheel is input', (tester) async {
      await pumpIdle(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(10, 10)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      expect(use.isActive, isTrue);
    });

    testWidgets('a trackpad scroll is input', (tester) async {
      await pumpIdle(tester);
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(
        pointer.panZoomStart(const Offset(10, 10)),
      );
      advance(const Duration(minutes: 1));
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(const Offset(10, 10), pan: const Offset(0, 20)),
      );
      expect(use.isActive, isTrue);
      await tester.sendEventToBinding(pointer.panZoomEnd());
    });

    testWidgets('a key is input, and is left for the app', (tester) async {
      await pumpIdle(tester);
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(use.isActive, isTrue);
      expect(handled, isFalse);
    });

    testWidgets('a mouse passing over is not input', (tester) async {
      await pumpIdle(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(10, 10)));
      await tester.sendEventToBinding(pointer.hover(const Offset(40, 40)));
      expect(use.isActive, isFalse);
    });

    testWidgets('nothing counts once detached', (tester) async {
      await pumpIdle(tester);
      signals.detach();
      attached = false;
      final gesture = await tester.startGesture(const Offset(10, 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      expect(use.isActive, isFalse);
      await gesture.up();
    });
  });
}
