// Kept separate from resizable_pane_test.dart so the widget binding remains
// absent and the controller's pure-Dart notification contract is exercised.
import 'dart:async';

import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flush owns pending durability and orders later widths', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final writes = <double>[];
    var active = 0;
    var peak = 0;
    double? durable;
    final controller = PanelWidthController(
      initialWidth: 240,
      minimumWidth: 200,
      writeWidth: (width) async {
        active++;
        if (active > peak) peak = active;
        writes.add(width);
        if (width == 250) {
          started.complete();
          await release.future;
        }
        durable = width;
        active--;
      },
    );
    addTearDown(controller.dispose);
    controller.resizeBy(10);
    final first = controller.flush();
    await started.future;
    var joinedSettled = false;
    final joined = controller.flush().then((_) => joinedSettled = true);
    await Future<void>.delayed(Duration.zero);
    expect(joinedSettled, isFalse);
    controller.resizeBy(10);
    final newest = controller.flush();
    await Future<void>.delayed(Duration.zero);
    expect(writes, [250]);
    release.complete();
    await Future.wait([first, joined, newest]);
    expect(peak, 1);
    expect(writes, [250, 260]);
    expect(durable, 260);
  });

  test(
    'a failed flush preserves the accepted width for explicit retry',
    () async {
      var attempts = 0;
      double? durable;
      final controller = PanelWidthController(
        initialWidth: 240,
        minimumWidth: 200,
        writeWidth: (width) async {
          attempts++;
          if (attempts == 1) throw StateError('storage unavailable');
          durable = width;
        },
      );
      addTearDown(controller.dispose);
      controller.resizeBy(10);
      await expectLater(controller.flush(), throwsStateError);
      await controller.flush();
      expect(attempts, 2);
      expect(durable, 250);
    },
  );

  test('uncapped widths restore and survive temporary layout limits', () async {
    final writes = <double>[];
    final controller = PanelWidthController(
      initialWidth: 320,
      minimumWidth: 320,
      readWidth: () async => 1200,
      writeWidth: (width) async => writes.add(width),
    );
    addTearDown(controller.dispose);
    await controller.restored;

    expect(controller.value, 1200);
    expect(controller.effectiveWidth(maximum: 800), 800);
    expect(controller.resizeBy(100, maximum: 800), isFalse);
    expect(controller.effectiveWidth(maximum: 1600), 1200);
    controller.resizeBy(200, maximum: 1600);
    await controller.flush();
    expect(writes, [1400]);
    controller.resizeBy(-2000, maximum: 1600);
    expect(controller.value, 320);
  });

  test(
    'notifies synchronously and flushes without a scheduler binding',
    () async {
      final writes = <double>[];
      final controller = PanelWidthController(
        initialWidth: 240,
        minimumWidth: 200,
        maximumWidth: 480,
        writeWidth: (width) async => writes.add(width),
      );
      addTearDown(controller.dispose);
      final seen = <double>[];
      controller.addListener(() => seen.add(controller.value));

      controller.resizeBy(16);

      expect(seen, [256]);
      expect(writes, isEmpty);
      await controller.flush();
      expect(writes, [256]);
    },
  );

  test(
    'a resize prevents a stale restoration from replacing its width',
    () async {
      final read = Completer<double?>();
      final controller = PanelWidthController(
        initialWidth: 240,
        minimumWidth: 200,
        maximumWidth: 480,
        readWidth: () => read.future,
      );
      addTearDown(controller.dispose);

      controller.resizeBy(16);
      read.complete(480);
      await controller.restored;

      expect(controller.value, 256);
    },
  );
}
