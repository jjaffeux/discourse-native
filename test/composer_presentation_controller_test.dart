import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/shell/composer/presentation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a reentrant dock choice remains the durable preference', () async {
    final store = ComposerLayoutStore(persistence: _MemoryLayout());
    final controller = ComposerPresentationController(store: store);
    addTearDown(controller.dispose);
    var replaced = false;
    controller.addListener(() {
      if (replaced) return;
      replaced = true;
      controller.dock(ComposerPlacement.bottom);
    });

    controller.dock(ComposerPlacement.left);
    expect(controller.preference.placement, ComposerPlacement.bottom);
    final reopened = ComposerPresentationController(store: store);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.preference.placement, ComposerPlacement.bottom);
  });

  test('a reentrant resize remains the durable geometry', () async {
    final store = ComposerLayoutStore(persistence: _MemoryLayout());
    final controller = ComposerPresentationController(store: store);
    addTearDown(controller.dispose);
    var replaced = false;
    controller.addListener(() {
      if (replaced) return;
      replaced = true;
      controller.resize(
        placement: ComposerPlacement.right,
        extent: 640,
        topic: false,
      );
    });

    controller.resize(
      placement: ComposerPlacement.right,
      extent: 480,
      topic: false,
    );
    expect(controller.preference.sideWidth, 640);
    final reopened = ComposerPresentationController(store: store);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.preference.sideWidth, 640);
  });

  test('a transient resize keeps the last accepted durable geometry', () async {
    final store = ComposerLayoutStore(persistence: _MemoryLayout());
    final controller = ComposerPresentationController(store: store);
    addTearDown(controller.dispose);
    controller.resize(
      placement: ComposerPlacement.right,
      extent: 480,
      topic: false,
    );
    controller.resize(
      placement: ComposerPlacement.right,
      extent: 640,
      topic: false,
      persist: false,
    );
    expect(controller.preference.sideWidth, 640);
    final reopened = ComposerPresentationController(store: store);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.preference.sideWidth, 480);
  });
}

final class _MemoryLayout implements ComposerLayoutPersistence {
  String? _value;

  @override
  Future<String?> readLayout() async => _value;

  @override
  Future<bool> writeLayout(String encoded) async {
    _value = encoded;
    return true;
  }
}
