import 'dart:convert';
import 'dart:isolate';

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

  test('projects a small response in the requested worker isolate', () async {
    final result = await decodeAndProjectJsonHttpResponse(
      http.Response('{"value":42}', 200),
      project: _projectWithIsolate,
      backgroundThreshold: 0,
    );

    expect(result.isolate, isNot(Isolate.current.controlPort));
    expect(result.value, {'value': 42});
  });

  test('projects below the threshold on the caller isolate', () async {
    final result = await decodeAndProjectJsonHttpResponse(
      http.Response('{"value":42}', 200),
      project: _projectWithIsolate,
    );

    expect(result.isolate, Isolate.current.controlPort);
    expect(result.value, {'value': 42});
  });

  test('projection preserves HTTP charset selection', () async {
    for (final headers in [
      {'content-type': 'application/json; charset=iso-8859-1'},
      <String, String>{},
    ]) {
      final result = await decodeAndProjectJsonHttpResponse(
        http.Response.bytes(
          latin1.encode('{"value":"café"}'),
          200,
          headers: headers,
        ),
        project: _projectWithIsolate,
        backgroundThreshold: 0,
      );
      expect(result.value, {'value': 'café'});
    }
  });

  test(
    'propagates outer JSON and projection failures from the worker',
    () async {
      await expectLater(
        decodeAndProjectJsonHttpResponse(
          http.Response('{', 200),
          project: _projectWithIsolate,
          backgroundThreshold: 0,
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        decodeAndProjectJsonHttpResponse<Object?>(
          http.Response('{}', 200),
          project: _rejectProjection,
          backgroundThreshold: 0,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'projection failed',
          ),
        ),
      );
    },
  );
}

({SendPort isolate, Object? value}) _projectWithIsolate(Object? value) =>
    (isolate: Isolate.current.controlPort, value: value);

Object? _rejectProjection(Object? value) =>
    throw StateError('projection failed');
