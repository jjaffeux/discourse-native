import 'dart:convert';

import 'package:discourse_native/src/data/json_decode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('decodes small responses without requiring a worker isolate', () async {
    expect(await decodeJsonResponse('{"topic":{"id":42}}'), {
      'topic': {'id': 42},
    });
  });

  test('decodes large responses on the background path', () async {
    final padding = 'x' * 1024;

    expect(
      await decodeJsonResponse('{"value":"$padding"}', backgroundThreshold: 1),
      {'value': padding},
    );
  });

  test('propagates malformed JSON from the background path', () async {
    await expectLater(
      decodeJsonResponse('{', backgroundThreshold: 1),
      throwsA(isA<FormatException>()),
    );
  });

  test('decodes response bytes and their charset off the UI path', () async {
    final response = http.Response.bytes(
      utf8.encode('{"value":"café"}'),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    expect(await decodeJsonHttpResponse(response, backgroundThreshold: 1), {
      'value': 'café',
    });
  });
}
