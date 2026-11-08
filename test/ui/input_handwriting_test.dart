import 'dart:async';

import 'package:discourse_native/src/ui/foundation/input_handwriting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (model, enabled) in [
    ('iPhone', false),
    ('iPad', true),
    ('iPod touch', true),
    ('', true),
    ('Unknown', true),
  ]) {
    test('native model "$model" keeps handwriting=$enabled', () async {
      var requests = 0;
      final handwriting = InputHandwriting(
        loadIosModel: () async {
          requests++;
          return model;
        },
      );
      addTearDown(handwriting.dispose);

      expect(handwriting.value, isTrue);
      await handwriting.ensureLoaded();
      expect(handwriting.value, enabled);
      await handwriting.ensureLoaded();
      expect(requests, 1);
    });
  }

  test(
    'a failed native query preserves handwriting and is not repeated',
    () async {
      var requests = 0;
      final handwriting = InputHandwriting(
        loadIosModel: () async {
          requests++;
          throw StateError('Device information unavailable');
        },
      );
      addTearDown(handwriting.dispose);

      await handwriting.ensureLoaded();
      expect(handwriting.value, isTrue);
      await handwriting.ensureLoaded();
      expect(requests, 1);
    },
  );

  test('concurrent inputs share a pending native query', () async {
    final model = Completer<String>();
    var requests = 0;
    final handwriting = InputHandwriting(
      loadIosModel: () {
        requests++;
        return model.future;
      },
    );
    addTearDown(handwriting.dispose);

    final first = handwriting.ensureLoaded();
    final second = handwriting.ensureLoaded();
    expect(requests, 1);
    expect(handwriting.value, isTrue);
    model.complete('iPad');
    await Future.wait([first, second]);
    expect(handwriting.value, isTrue);
  });
}
