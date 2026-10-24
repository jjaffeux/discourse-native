import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('audio keyboard seeks in $direction', (tester) async {
      var position = const Duration(seconds: 30);
      final seeks = <Duration>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: direction,
            child: StatefulBuilder(
              builder: (context, update) => DAudioPlayer(
                title: 'Recording',
                position: position,
                duration: const Duration(minutes: 1),
                onPlayPause: () {},
                onSeek: (value) => update(() {
                  position = value;
                  seeks.add(value);
                }),
              ),
            ),
          ),
        ),
      );
      await _press(tester, LogicalKeyboardKey.tab);
      final forward = direction == TextDirection.ltr
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
      final backward = direction == TextDirection.ltr
          ? LogicalKeyboardKey.arrowLeft
          : LogicalKeyboardKey.arrowRight;

      await _press(tester, forward);
      expect(seeks, [const Duration(seconds: 31)]);
      await _press(tester, backward);
      expect(seeks.last, const Duration(seconds: 30));
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(seeks.last, const Duration(seconds: 31));
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(seeks.last, const Duration(seconds: 30));
      await _press(tester, LogicalKeyboardKey.pageUp);
      expect(seeks.last, const Duration(seconds: 40));
      await _press(tester, LogicalKeyboardKey.pageDown);
      expect(seeks.last, const Duration(seconds: 30));
      await _press(tester, forward, shift: true);
      expect(seeks.last, const Duration(seconds: 40));
      await _press(tester, backward, shift: true);
      expect(seeks.last, const Duration(seconds: 30));
      await _press(tester, LogicalKeyboardKey.arrowUp, shift: true);
      expect(seeks.last, const Duration(seconds: 40));
      await _press(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(seeks.last, const Duration(seconds: 30));
      await _press(tester, LogicalKeyboardKey.end);
      expect(seeks.last, const Duration(minutes: 1));
      final atEnd = List<Duration>.of(seeks);
      await _press(tester, LogicalKeyboardKey.pageUp);
      await _press(tester, forward, shift: true);
      expect(seeks, atEnd);
      await _press(tester, LogicalKeyboardKey.home);
      expect(seeks.last, Duration.zero);
      final atStart = List<Duration>.of(seeks);
      await _press(tester, LogicalKeyboardKey.pageDown);
      await _press(tester, backward, shift: true);
      expect(seeks, atStart);
      expect(position, Duration.zero);
    });
  }

  for (final duration in [
    const Duration(seconds: 4),
    const Duration(milliseconds: 750),
  ]) {
    testWidgets('coarse audio keys reach short clip endpoints at $duration', (
      tester,
    ) async {
      var position = Duration.zero;
      final seeks = <Duration>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => DAudioPlayer(
              title: 'Short recording',
              position: position,
              duration: duration,
              onPlayPause: () {},
              onSeek: (value) => update(() {
                position = value;
                seeks.add(value);
              }),
            ),
          ),
        ),
      );
      await _press(tester, LogicalKeyboardKey.tab);
      await _press(tester, LogicalKeyboardKey.pageUp);
      expect(seeks, [duration]);
      await _press(tester, LogicalKeyboardKey.pageDown);
      expect(seeks, [duration, Duration.zero]);
      await _press(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(seeks, [duration, Duration.zero, duration]);
      await _press(tester, LogicalKeyboardKey.arrowLeft, shift: true);
      expect(seeks, [duration, Duration.zero, duration, Duration.zero]);
    });
  }

  for (final state in ['disabled', 'loading', 'no duration']) {
    testWidgets('audio seek keys stop when $state and resume when ready', (
      tester,
    ) async {
      var blocked = false;
      var position = const Duration(seconds: 30);
      final seeks = <Duration>[];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return DAudioPlayer(
                title: 'Recording',
                position: position,
                duration: blocked && state == 'no duration'
                    ? Duration.zero
                    : const Duration(minutes: 1),
                loading: blocked && state == 'loading',
                onPlayPause: () {},
                onSeek: blocked && state == 'disabled'
                    ? null
                    : (value) => update(() {
                        position = value;
                        seeks.add(value);
                      }),
              );
            },
          ),
        ),
      );
      await _press(tester, LogicalKeyboardKey.tab);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(seeks, [const Duration(seconds: 31)]);
      update(() => blocked = true);
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ]) {
        await _press(tester, key);
        await _press(tester, key, shift: true);
      }
      expect(seeks, [const Duration(seconds: 31)]);
      update(() => blocked = false);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.tab);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(seeks, [const Duration(seconds: 31), const Duration(seconds: 32)]);
    });
  }
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}
