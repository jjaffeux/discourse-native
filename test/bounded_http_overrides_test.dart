import 'dart:io';

import 'package:discourse_native/src/data/bounded_http_overrides.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('caps clients while preserving a stricter inherited limit', () {
    final previous = _FakeOverrides(limit: 12);
    final bounded = BoundedHttpOverrides(
      maxConnectionsPerHost: 4,
      previous: previous,
    );

    final client = bounded.createHttpClient(null);
    expect(client.maxConnectionsPerHost, 4);
    expect(previous.clientsCreated, 1);

    previous.client.maxConnectionsPerHost = 2;
    expect(bounded.createHttpClient(null).maxConnectionsPerHost, 2);
  });
}

final class _FakeOverrides extends HttpOverrides {
  _FakeOverrides({required int limit})
    : client = _FakeHttpClient(maxConnectionsPerHost: limit);

  final _FakeHttpClient client;
  int clientsCreated = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientsCreated++;
    return client;
  }
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({this.maxConnectionsPerHost});

  @override
  int? maxConnectionsPerHost;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
