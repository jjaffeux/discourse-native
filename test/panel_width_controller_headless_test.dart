// Kept separate from resizable_pane_test.dart so the widget binding remains
// absent and the controller's pure-Dart notification contract is exercised.
import 'dart:async';

import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
