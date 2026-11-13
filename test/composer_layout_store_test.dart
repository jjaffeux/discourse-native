import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overlapping layout reads share a snapshot until a write', () async {
    final persistence = _HeldLayoutPersistence();
    final first = ComposerLayoutStore(persistence: persistence);
    final second = ComposerLayoutStore(persistence: persistence);

    final before = first.read();
    final joined = second.read();
    final saving = second.write(const ComposerLayoutPreference(sideWidth: 500));
    final after = first.read();
    persistence.release.complete();

    expect((await before).sideWidth, 420);
    expect(await joined, same(await before));
    await saving;
    expect((await after).sideWidth, 500);
    expect(persistence.reads, 2);
  });

  test(
    'a layout burst writes only its active and newest pending snapshot',
    () async {
      final persistence = _HeldLayoutPersistence();
      final store = ComposerLayoutStore(persistence: persistence);
      final first = store.write(const ComposerLayoutPreference(sideWidth: 400));
      await persistence.started.future;
      final saves = [
        for (var width = 401; width <= 500; width++)
          store.write(ComposerLayoutPreference(sideWidth: width.toDouble())),
      ];
      final read = ComposerLayoutStore(persistence: persistence).read();
      persistence.release.complete();
      await Future.wait([first, ...saves]);
      expect(persistence.widths, [400, 500]);
      expect((await read).sideWidth, 500);
    },
  );
}

final class _HeldLayoutPersistence implements ComposerLayoutPersistence {
  final started = Completer<void>();
  final release = Completer<void>();
  final widths = <num>[];
  String? value;
  int reads = 0;

  @override
  Future<String?> readLayout() async {
    reads++;
    return value;
  }

  @override
  Future<bool> writeLayout(String encoded) async {
    widths.add(
      (jsonDecode(encoded) as Map<String, dynamic>)['sideWidth'] as num,
    );
    if (widths.length == 1) {
      started.complete();
      await release.future;
    }
    value = encoded;
    return true;
  }
}
