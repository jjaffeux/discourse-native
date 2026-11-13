import 'dart:async';
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

ByteCacheDownload _download() => (
  response: http.Response.bytes(Uint8List.fromList([1]), 200),
  oversized: false,
  persistable: true,
);

void main() {
  test(
    'a failed transfer does not strand a caller in another error zone',
    () async {
      final pool = ByteCacheRequestPool();
      addTearDown(pool.close);
      final response = Completer<ByteCacheDownload>();
      final first = pool.run('url', () => response.future);
      final failure = expectLater(first, throwsStateError);
      final peer = Completer<ByteCacheDownload>();
      runZonedGuarded(
        () {
          unawaited(
            pool
                .run('url', () async => _download())
                .then<void>(peer.complete, onError: peer.completeError),
          );
        },
        (error, stack) {
          if (!peer.isCompleted) peer.completeError(error, stack);
        },
      );
      final observed = peer.future.timeout(const Duration(seconds: 1));
      response.completeError(StateError('failed download'));

      await failure;
      expect((await observed).response.bodyBytes, [1]);
    },
  );

  test('synchronous reentry joins the registered transfer', () async {
    final pool = ByteCacheRequestPool();
    addTearDown(pool.close);
    final response = Completer<ByteCacheDownload>();
    late Future<ByteCacheDownload> peer;
    var calls = 0;
    final first = pool.run('url', () {
      calls++;
      peer = pool.run('url', () async {
        calls++;
        return _download();
      });
      return response.future;
    });
    response.complete(_download());
    expect((await peer).response, same((await first).response));
    expect(calls, 1);
  });

  test(
    'synchronous failures use the future contract and permit retry',
    () async {
      final pool = ByteCacheRequestPool();
      addTearDown(pool.close);
      Future<ByteCacheDownload>? result;
      Object? synchronousError;
      try {
        result = pool.run('url', () => throw StateError('failed download'));
      } catch (error) {
        synchronousError = error;
      }
      if (result != null) await expectLater(result, throwsStateError);
      expect(synchronousError, isNull);
      expect(
        (await pool.run('url', () async => _download())).response.bodyBytes,
        [1],
      );
    },
  );
}
