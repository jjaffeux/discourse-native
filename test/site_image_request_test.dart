import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fakes.dart';

void main() {
  const site = 'https://forum.example';
  const url = '$site/image';

  test(
    'a released request shares transport with another consumer and a save',
    () async {
      final client = _Client();
      final repository = SiteImageRepository(
        credentials: FakeApiCredentialReader(),
        lifecycle: SiteLifecycle(),
        client: client,
      );
      addTearDown(repository.dispose);
      final first = repository.request(siteUrl: site, url: url);
      final second = repository.request(siteUrl: site, url: url)
        ..setVisible(true);
      final save = repository.load(siteUrl: site, url: url);
      await _pump();
      expect(client.sent, hasLength(1));
      first.release();
      expect(await first.result, isNull);
      expect(client.sent.single.aborted, isFalse);
      client.sent.single.complete([1, 2]);
      expect((await second.result)?.bytes, [1, 2]);
      expect((await save)?.bytes, [1, 2]);
      expect((await repository.load(siteUrl: site, url: url))?.bytes, [1, 2]);
      expect(client.sent, hasLength(1));
    },
  );

  test(
    'release during credential opening settles promptly and starts no transfer',
    () async {
      final credentials = _Credentials();
      final client = _Client();
      final repository = SiteImageRepository(
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        client: client,
      );
      addTearDown(repository.dispose);
      final abandoned = repository.request(siteUrl: site, url: url)
        ..setVisible(true);
      abandoned.release();
      expect(await abandoned.result, isNull);
      credentials.keys.single.complete('key');
      await _pump();
      expect(client.sent, isEmpty);
      final revisit = repository.request(siteUrl: site, url: url);
      await _pump();
      expect(client.sent, hasLength(1));
      client.sent.single.complete([2]);
      expect((await revisit.result)?.bytes, [2]);
    },
  );

  test(
    'retirement during opening cannot attach old demand to a new account',
    () async {
      final credentials = _Credentials();
      final lifecycle = SiteLifecycle();
      final client = _Client();
      final repository = SiteImageRepository(
        credentials: credentials,
        lifecycle: lifecycle,
        client: client,
      );
      addTearDown(repository.dispose);
      final old = repository.request(siteUrl: site, url: url);
      lifecycle.invalidate(site);
      expect(await old.result, isNull);
      final fresh = repository.request(siteUrl: site, url: url);
      expect(credentials.keys, hasLength(2));
      credentials.keys[1].complete('new-key');
      await _pump();
      expect(client.sent.single.headers['User-Api-Key'], 'new-key');
      credentials.keys[0].complete('old-key');
      await _pump();
      expect(client.sent, hasLength(1));
      client.sent.single.complete([7]);
      expect((await fresh.result)?.bytes, [7]);
    },
  );

  test(
    'active account retirement cancels old bytes and a new account refetches',
    () async {
      final credentials = FakeApiCredentialReader()..keys[site] = 'old-key';
      final lifecycle = SiteLifecycle();
      final client = _Client();
      final repository = SiteImageRepository(
        credentials: credentials,
        lifecycle: lifecycle,
        client: client,
      );
      addTearDown(repository.dispose);
      final old = repository.request(siteUrl: site, url: url);
      await _pump();
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(onCancel: cancelled.complete);
      client.sent.single.response.complete(
        http.StreamedResponse(body.stream, 200),
      );
      await _pump();
      body.add([1]);
      lifecycle.invalidate(site);
      expect(await old.result, isNull);
      await cancelled.future;
      credentials.keys[site] = 'new-key';
      final fresh = repository.request(siteUrl: site, url: url);
      await _pump();
      expect(client.sent, hasLength(2));
      expect(client.sent.last.headers['User-Api-Key'], 'new-key');
      client.sent.last.complete([2]);
      expect((await fresh.result)?.bytes, [2]);
      expect(repository.cached(siteUrl: site, url: url)?.bytes, [2]);
      await body.close();
    },
  );

  test(
    'forget retires pending handles and late opening cannot replace a revisit',
    () async {
      final credentials = _Credentials();
      final client = _Client();
      final repository = SiteImageRepository(
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        client: client,
      );
      addTearDown(repository.dispose);
      final old = repository.request(siteUrl: site, url: url);
      repository.forget(site);
      expect(await old.result, isNull);
      final fresh = repository.request(siteUrl: site, url: url);
      credentials.keys[1].complete('fresh');
      await _pump();
      credentials.keys[0].complete('stale');
      await _pump();
      expect(client.sent, hasLength(1));
      expect(client.sent.single.headers['User-Api-Key'], 'fresh');
      client.sent.single.complete([3]);
      expect((await fresh.result)?.bytes, [3]);
    },
  );

  test(
    'dispose while credentials open settles consumers and never sends',
    () async {
      final credentials = _Credentials();
      final client = _Client();
      final repository = SiteImageRepository(
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        client: client,
      );
      final pending = repository.request(siteUrl: site, url: url);
      repository.dispose();
      expect(await pending.result, isNull);
      credentials.keys.single.complete('retired');
      await _pump();
      expect(client.sent, isEmpty);
      expect(await repository.request(siteUrl: site, url: url).result, isNull);
    },
  );
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

final class _Credentials implements ApiCredentialReader {
  final List<Completer<String?>> keys = [];
  @override
  Future<String?> apiKeyFor(String siteUrl) {
    final key = Completer<String?>();
    keys.add(key);
    return key.future;
  }

  @override
  Future<String> clientId() async => '';
}

final class _Client extends http.BaseClient {
  final List<_Sent> sent = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final entry = _Sent(request.headers);
    sent.add(entry);
    if (request is http.Abortable && request.abortTrigger != null) {
      unawaited(request.abortTrigger!.then((_) => entry.aborted = true));
    }
    return entry.response.future;
  }
}

final class _Sent {
  _Sent(this.headers);
  final Map<String, String> headers;
  final Completer<http.StreamedResponse> response = Completer();
  bool aborted = false;
  void complete(List<int> bytes) =>
      response.complete(http.StreamedResponse(Stream.value(bytes), 200));
}
