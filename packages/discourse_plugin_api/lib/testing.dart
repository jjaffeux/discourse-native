library;

import 'dart:async';
import 'dart:collection';

import 'discourse_plugin_api.dart';

typedef PluginTransportRequest = ({
  String siteUrl,
  String method,
  String path,
  String? apiKey,
  String? clientId,
  Map<String, Object?> body,
  bool expectsList,
});

typedef PluginTransportResponder =
    FutureOr<Object?> Function(PluginTransportRequest request);

/// Routes use uppercase-method/full-path keys. Missing routes and response-shape
/// mismatches throw; configured failures are consumed once for retry tests.
class RecordingPluginTransport
    implements PluginApiTransport, PluginJsonListTransport {
  RecordingPluginTransport({
    Map<String, Map<String, dynamic>> responses = const {},
    Map<String, List<Map<String, dynamic>>> listResponses = const {},
    Map<String, Object> failures = const {},
    Map<String, PluginTransportResponder> responders = const {},
  }) : responses = Map.of(responses),
       listResponses = Map.of(listResponses),
       failures = Map.of(failures),
       responders = Map.of(responders);

  final Map<String, Map<String, dynamic>> responses;

  final Map<String, List<Map<String, dynamic>>> listResponses;

  final Map<String, Object> failures;

  /// Responders take precedence over static responses. Their result is checked
  /// against the object/list shape requested by the caller.
  final Map<String, PluginTransportResponder> responders;

  final List<PluginTransportRequest> _requests = [];
  final List<PluginTransportRequest> _reads = [];
  final List<PluginTransportRequest> _writes = [];

  late final List<PluginTransportRequest> requests = UnmodifiableListView(
    _requests,
  );
  late final List<PluginTransportRequest> reads = UnmodifiableListView(_reads);
  late final List<PluginTransportRequest> writes = UnmodifiableListView(
    _writes,
  );

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final request = _recordRead(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
      expectsList: false,
    );
    return _objectResponse(await _responseFor(request));
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final request = _recordRead(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
      expectsList: true,
    );
    return _listResponse(await _responseFor(request));
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    final request = _recordWrite(
      siteUrl: siteUrl,
      path: path,
      method: method,
      apiKey: apiKey,
      clientId: clientId,
      body: body,
    );
    return _objectResponse(await _responseFor(request));
  }

  PluginTransportRequest _recordRead({
    required String siteUrl,
    required String path,
    required String? apiKey,
    required String? clientId,
    required bool expectsList,
  }) {
    final request = (
      siteUrl: siteUrl,
      method: 'GET',
      path: path,
      apiKey: apiKey,
      clientId: clientId,
      body: const <String, Object?>{},
      expectsList: expectsList,
    );
    _requests.add(request);
    _reads.add(request);
    return request;
  }

  PluginTransportRequest _recordWrite({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required String? clientId,
    required Map<String, Object?> body,
  }) {
    final request = (
      siteUrl: siteUrl,
      method: method.toUpperCase(),
      path: path,
      apiKey: apiKey,
      clientId: clientId,
      body: _freezeMap(body),
      expectsList: false,
    );
    _requests.add(request);
    _writes.add(request);
    return request;
  }

  Future<Object?> _responseFor(PluginTransportRequest request) async {
    final route = '${request.method} ${request.path}';
    final failure = failures.remove(route);
    if (failure != null) throw failure;

    final responder = responders[route];
    if (responder != null) return responder(request);

    if (request.expectsList) {
      if (listResponses.containsKey(route)) return listResponses[route];
      if (responses.containsKey(route)) {
        throw StateError(
          '$route has an object response but was requested as a JSON list.',
        );
      }
    } else {
      if (responses.containsKey(route)) return responses[route];
      if (listResponses.containsKey(route)) {
        throw StateError(
          '$route has a list response but was requested as a JSON object.',
        );
      }
    }
    throw StateError(
      'No ${request.expectsList ? 'list' : 'object'} response configured for '
      '$route.',
    );
  }

  Map<String, dynamic> _objectResponse(Object? value) {
    if (value is! Map) {
      throw StateError(
        'Plugin transport responder returned ${value.runtimeType}; expected a '
        'JSON object.',
      );
    }
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw StateError(
          'Plugin transport responder returned an object with a '
          '${key.runtimeType} key; expected String keys.',
        );
      }
      result[key] = entry.value;
    }
    return result;
  }

  List<Map<String, dynamic>> _listResponse(Object? value) {
    if (value is! List) {
      throw StateError(
        'Plugin transport responder returned ${value.runtimeType}; expected a '
        'JSON list.',
      );
    }
    return List.unmodifiable([for (final item in value) _objectResponse(item)]);
  }
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    Map.unmodifiable({
      for (final entry in source.entries) entry.key: _freezeJson(entry.value),
    });

Object? _freezeJson(Object? value) => switch (value) {
  final Map<String, Object?> map => _freezeMap(map),
  final Map<Object?, Object?> map => Map<Object?, Object?>.unmodifiable({
    for (final entry in map.entries) entry.key: _freezeJson(entry.value),
  }),
  final List<Object?> list => List<Object?>.unmodifiable(list.map(_freezeJson)),
  _ => value,
};
