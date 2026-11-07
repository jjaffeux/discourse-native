import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/composer_layout_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  @override
  Future<String?> readLayout() async => value;

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
