import 'package:discourse_native/src/data/request_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'nested reciprocal joins preserve background and observe promotion',
    () async {
      final source = RequestIntent.background();
      final first = RequestIntentGroup(source);
      final second = RequestIntentGroup(first);
      first.join(second);
      expect(first.isInteractive, isFalse);
      expect(second.isInteractive, isFalse);
      await first.run(() async {
        await Future<void>.value();
        expect(RequestIntent.current, same(first));
      });
      source.promote();
      expect(first.isInteractive, isTrue);
      expect(second.isInteractive, isTrue);
      expect(RequestIntent.current.isInteractive, isTrue);
    },
  );
}
