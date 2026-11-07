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
