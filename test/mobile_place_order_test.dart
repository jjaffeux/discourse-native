import 'dart:async';

import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:discourse_native/src/shell/mobile_place_order.dart';
import 'package:flutter_test/flutter_test.dart';

class _Persistence implements ScalarPreferencePersistence<List<String>> {
  final values = <String, List<String>>{};
  final written = <List<String>>[];
  Completer<List<String>?>? readGate;
  Completer<void>? writeGate;
  final writeStarted = Completer<void>();
  @override
  Future<List<String>?> read(String key) async =>
      readGate == null ? values[key] : readGate!.future;
  @override
  Future<bool> write(String key, List<String> value) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    values[key] = value;
    written.add(value);
    return true;
  }
}

const _site = 'https://places.example';

MobilePlaceOrderController _controller(
  _Persistence persistence, {
  String site = _site,
  String account = 'user:reader',
}) => MobilePlaceOrderController(site, account, persistence: persistence);

void main() {
  group('applying a saved order', () {
    List<String> apply(List<String> places, List<String> order) =>
        MobilePlaceOrderController.apply(places, order, (place) => place);

    test('nothing saved keeps the default order', () {
      expect(apply(['a', 'b', 'c'], []), ['a', 'b', 'c']);
    });

    test('the places named come first, in their saved sequence, and the '
        'rest keep their default order after them', () {
      expect(apply(['a', 'b', 'c', 'd'], ['c', 'a']), ['c', 'a', 'b', 'd']);
      expect(apply(['a', 'b', 'c'], ['c', 'b', 'a']), ['c', 'b', 'a']);
    });

    test('a name the forum no longer offers is dropped', () {
      expect(apply(['a', 'b', 'c'], ['c', 'gone', 'a']), ['c', 'a', 'b']);
      expect(apply(['a', 'b'], ['gone']), ['a', 'b']);
    });

    test('a place offered anew takes its default position among the '
        'unplaced', () {
      expect(apply(['a', 'new', 'b', 'c'], ['c', 'a']), ['c', 'a', 'new', 'b']);
    });
  });

  test('the order round trips within the account alone', () async {
    final persistence = _Persistence();
    final controller = _controller(persistence);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.order, isEmpty);
    await controller.set(['users', 'topics']);
    final restored = _controller(persistence);
    final otherUser = _controller(persistence, account: 'user:other');
    final otherSite = _controller(persistence, site: 'https://b.example');
    addTearDown(restored.dispose);
    addTearDown(otherUser.dispose);
    addTearDown(otherSite.dispose);
    await restored.load();
    await otherUser.load();
    await otherSite.load();
    expect(restored.order, ['users', 'topics']);
    expect(otherUser.order, isEmpty);
    expect(otherSite.order, isEmpty);
  });

  test('of two quick moves, the second\'s write lands last and wins', () async {
    final persistence = _Persistence()..writeGate = Completer<void>();
    final controller = _controller(persistence);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final first = controller.set(['b', 'a', 'c']);
    await persistence.writeStarted.future;
    final second = controller.set(['c', 'b', 'a']);
    // Both moves have shown at once; neither waited on the store.
    expect(controller.order, ['c', 'b', 'a']);
    expect(notifications, 2);
    persistence.writeGate!.complete();
    await Future.wait([first, second]);
    expect(persistence.written, [
      ['b', 'a', 'c'],
      ['c', 'b', 'a'],
    ]);
    final restored = _controller(persistence);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.order, ['c', 'b', 'a']);
  });

  test('a move wins over a late persisted read', () async {
    final persistence = _Persistence()..readGate = Completer();
    final controller = _controller(persistence);
    addTearDown(controller.dispose);
    final loading = controller.load();
    final saving = controller.set(['b', 'a']);
    persistence.readGate!.complete(['a', 'b']);
    await loading;
    await saving;
    expect(controller.order, ['b', 'a']);
  });

  test('setting the order it already has writes nothing', () async {
    final persistence = _Persistence();
    final controller = _controller(persistence);
    addTearDown(controller.dispose);
    await controller.set(['a', 'b']);
    await controller.set(['a', 'b']);
    expect(persistence.written, [
      ['a', 'b'],
    ]);
  });

  for (final removed in [false, true]) {
    test(
      'a queued write retires on ${removed ? 'forum removal' : 'disposal'}',
      () async {
        final persistence = _Persistence()..writeGate = Completer<void>();
        final controller = _controller(persistence);
        if (removed) addTearDown(controller.dispose);
        final first = controller.set(['b', 'a']);
        await persistence.writeStarted.future;
        final queued = controller.set(['a', 'b']);
        if (removed) {
          await forgetSitePreferences([
            MobilePlaceOrderController.keys,
          ], () => ForgottenSites.removed(_site, keeping: []));
          expect(controller.order, isEmpty);
        } else {
          controller.dispose();
        }
        persistence.writeGate!.complete();
        await Future.wait([first, queued]);
        expect(persistence.written, [
          ['b', 'a'],
        ]);
      },
    );
  }

  test('a disposed controller cannot publish a read', () async {
    final persistence = _Persistence()..readGate = Completer();
    final controller = _controller(persistence);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final loading = controller.load();
    controller.dispose();
    persistence.readGate!.complete(['a']);
    await loading;
    expect(notifications, 0);
  });
}
