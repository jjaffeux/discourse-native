import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';

final class _GatedStorage implements ApiCredentialReader {
  final List<String> reads = [];
  final List<Completer<String?>> results = [];

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads.add(siteUrl);
    final result = Completer<String?>();
    results.add(result);
    return result.future;
  }

  @override
  Future<String> clientId() async => 'test-client';
}

void main() {
  group('ConnectedAccountCredentials', () {
    late _GatedStorage storage;
    late Set<String> connected;
    late ConnectedAccountCredentials credentials;

    setUp(() {
      storage = _GatedStorage();
      connected = {_siteUrl};
      credentials = ConnectedAccountCredentials(
        storage,
        isConnected: connected.contains,
      );
    });

    test('answers a connected site its stored key', () async {
      final read = credentials.apiKeyFor(_siteUrl);
      storage.results.single.complete('account-key');

      expect(await read, 'account-key');
    });

    test('never reads storage for a signed-out site', () async {
      connected.clear();

      expect(await credentials.apiKeyFor(_siteUrl), isNull);
      expect(storage.reads, isEmpty);
    });

    test('drops a key whose site signed out during the read', () async {
      final read = credentials.apiKeyFor(_siteUrl);
      expect(storage.reads, [_siteUrl]);

      connected.remove(_siteUrl);
      storage.results.single.complete('retired-key');

      expect(await read, isNull);
    });

    test('shares the client id whatever the account state', () async {
      connected.clear();

      expect(await credentials.clientId(), 'test-client');
    });
  });
}
