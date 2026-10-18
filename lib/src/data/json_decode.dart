import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Payloads below this size are cheaper to decode inline than to transfer to
/// a worker isolate. Large Discourse responses are decoded away from the UI
/// isolate so network completion cannot monopolize a frame.
const int backgroundJsonDecodeThreshold = 64 * 1024;

Future<Object?> decodeJsonResponse(
  String source, {
  int backgroundThreshold = backgroundJsonDecodeThreshold,
}) {
  if (source.length < backgroundThreshold) {
    return Future<Object?>.sync(() => jsonDecode(source));
  }
  return compute<String, Object?>(
    _decodeJson,
    source,
    debugLabel: 'Discourse JSON decode',
  );
}

Object? _decodeJson(String source) => jsonDecode(source);

Future<Object?> decodeJsonHttpResponse(
  http.Response response, {
  int backgroundThreshold = backgroundJsonDecodeThreshold,
}) => decodeJsonResponseBytes(
  response.bodyBytes,
  encodingName: _responseEncodingName(response.headers),
  backgroundThreshold: backgroundThreshold,
);

/// Decodes and projects together so only the resulting model leaves the worker.
Future<T> decodeAndProjectJsonHttpResponse<T>(
  http.Response response, {
  required T Function(Object?) project,
  int backgroundThreshold = backgroundJsonDecodeThreshold,
}) {
  final input = (
    input: (
      bytes: response.bodyBytes,
      encodingName: _responseEncodingName(response.headers),
    ),
    project: project,
  );
  if (response.bodyBytes.length < backgroundThreshold) {
    return Future<T>.sync(() => _decodeAndProjectEncodedJson(input));
  }
  return compute<_ProjectedEncodedJson<T>, T>(
    _decodeAndProjectEncodedJson<T>,
    input,
    debugLabel: 'Discourse JSON projection',
  );
}

Future<Object?> decodeJsonResponseBytes(
  Uint8List bytes, {
  String encodingName = 'utf-8',
  int backgroundThreshold = backgroundJsonDecodeThreshold,
}) {
  if (bytes.length < backgroundThreshold) {
    return Future<Object?>.sync(
      () => jsonDecode(_encoding(encodingName).decode(bytes)),
    );
  }
  return compute<_EncodedJson, Object?>(_decodeEncodedJson, (
    bytes: bytes,
    encodingName: encodingName,
  ), debugLabel: 'Discourse JSON decode');
}

typedef _EncodedJson = ({Uint8List bytes, String encodingName});

typedef _ProjectedEncodedJson<T> = ({
  _EncodedJson input,
  T Function(Object?) project,
});

T _decodeAndProjectEncodedJson<T>(_ProjectedEncodedJson<T> input) =>
    input.project(_decodeEncodedJson(input.input));

Object? _decodeEncodedJson(_EncodedJson input) =>
    jsonDecode(_encoding(input.encodingName).decode(input.bytes));

Encoding _encoding(String name) => Encoding.getByName(name) ?? utf8;

String _responseEncodingName(Map<String, String> headers) {
  final contentType = headers['content-type']?.toLowerCase();
  if (contentType != null) {
    final charset = RegExp(
      r'''charset\s*=\s*["']?([^;\s"']+)''',
    ).firstMatch(contentType)?.group(1);
    if (charset != null && Encoding.getByName(charset) != null) return charset;
    final mime = contentType.split(';').first.trim();
    if (mime == 'application/json' || mime.endsWith('+json')) return 'utf-8';
  }
  // Preserve package:http's compatibility fallback for responses which omit
  // a JSON content type. Real Discourse JSON responses declare UTF-8.
  return 'iso-8859-1';
}
