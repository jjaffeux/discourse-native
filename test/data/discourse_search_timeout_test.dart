import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _site = 'https://example.test/community';

void main() {
  for (final path in [
    '/search/query.json?term=test',
    '/search.json?q=test&page=1',
  ]) {
    testWidgets(
      '$path waits beyond ten seconds without changing credentials or subfolder',
      (tester) async {
        final client = _HeldClient();
        final searchApi = DiscourseApi(client: client);
        addTearDown(searchApi.close);
        final result = _Result(
          searchApi.pluginGetJson(
            siteUrl: _site,
            path: path,
            apiKey: 'search-key',
            clientId: 'search-client',
          ),
        );
        await tester.pump();
        expect(client.reads.single.request.url.toString(), '$_site$path');
        expect(
          client.reads.single.request.headers['User-Api-Key'],
          'search-key',
        );
        expect(
          client.reads.single.request.headers['User-Api-Client-Id'],
          'search-client',
        );
        await tester.pump(const Duration(seconds: 11));
        expect(result.done, isFalse);
        expect(client.reads.single.aborted, isFalse);
        client.reads.single.respond();
        await tester.pump();
        expect(result.done, isTrue);
        expect(result.error, isNull);
        expect(result.value, isEmpty);
      },
    );
  }

  testWidgets('legacy searchPosts uses the longer search deadline', (
    tester,
  ) async {
    final client = _HeldClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final result = _Result(
      api.searchPosts(siteUrl: _site, term: 'test', apiKey: 'key'),
    );
    await tester.pump();
    expect(
      client.reads.single.request.url.path,
      '/community/search/query.json',
    );
    expect(client.reads.single.request.url.queryParameters['term'], 'test');
    await tester.pump(const Duration(seconds: 11));
    expect(result.done, isFalse);
    client.reads.single.respond();
    await tester.pump();
    expect(result.error, isNull);
    expect(result.done, isTrue);
  });

  for (final path in [
    '/latest.json',
    '/chat/api/search.json?query=test',
    '/search/query.json/extra?term=test',
  ]) {
    testWidgets('$path retains the ordinary ten-second deadline', (
      tester,
    ) async {
      final client = _HeldClient();
      final api = DiscourseApi(client: client);
      addTearDown(api.close);
      final result = _Result(
        api.pluginGetJson(siteUrl: _site, path: path, apiKey: 'key'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(result.done, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(result.error, _timeoutFailure);
      expect(client.reads.single.aborted, isTrue);
    });
  }

  testWidgets('forum search aborts when its thirty-second deadline expires', (
    tester,
  ) async {
    final client = _HeldClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final result = _Result(
      api.pluginGetJson(
        siteUrl: _site,
        path: '/search/query.json?term=test',
        apiKey: 'key',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(result.done, isFalse);
    expect(client.reads.single.aborted, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(result.error, _timeoutFailure);
    expect(client.reads.single.aborted, isTrue);
  });

  testWidgets(
    'normal and search timeouts can be configured independently for both search callers',
    (tester) async {
      final client = _HeldClient();
      final api = DiscourseApi(
        client: client,
        timeout: const Duration(seconds: 4),
        searchTimeout: const Duration(seconds: 18),
      );
      addTearDown(api.close);
      final normal = _Result(
        api.pluginGetJson(siteUrl: _site, path: '/latest.json', apiKey: 'key'),
      );
      final search = _Result(
        api.pluginGetJson(
          siteUrl: _site,
          path: '/search.json?q=test',
          apiKey: 'key',
        ),
      );
      final legacy = _Result(
        api.searchPosts(siteUrl: _site, term: 'test', apiKey: 'key'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(normal.error, _timeoutFailure);
      expect(search.done, isFalse);
      expect(legacy.done, isFalse);
      await tester.pump(const Duration(seconds: 13));
      expect(search.done, isFalse);
      expect(legacy.done, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(search.error, _timeoutFailure);
      expect(legacy.error, _timeoutFailure);
      expect(client.reads.every((read) => read.aborted), isTrue);
    },
  );

  testWidgets(
    'coalescing separates different deadlines and credentials while sharing equal reads',
    (tester) async {
      final client = _HeldClient();
      final transport = DiscourseTransport.create(client: client);
      addTearDown(transport.close);
      final uri = Uri.parse('$_site/search/query.json?term=test');
      final normal = _Result(transport.get(uri, siteUrl: _site, apiKey: 'key'));
      final slow = _Result(
        transport.get(
          uri,
          siteUrl: _site,
          apiKey: 'key',
          requestTimeout: const Duration(seconds: 30),
        ),
      );
      final shared = _Result(
        transport.get(
          uri,
          siteUrl: _site,
          apiKey: 'key',
          requestTimeout: const Duration(seconds: 30),
        ),
      );
      final other = _Result(
        transport.get(
          uri,
          siteUrl: _site,
          apiKey: 'other-key',
          requestTimeout: const Duration(seconds: 30),
        ),
      );
      await tester.pump();
      expect(client.reads.length, 3);
      await tester.pump(const Duration(seconds: 11));
      expect(normal.error, _timeoutFailure);
      expect(slow.done, isFalse);
      expect(shared.done, isFalse);
      expect(other.done, isFalse);
      client.reads[1].respond();
      client.reads[2].respond();
      await tester.pump();
      expect(slow.value, same(shared.value));
      expect(other.value, isNot(same(slow.value)));
      expect(slow.error, isNull);
      expect(other.error, isNull);
    },
  );
}

final _timeoutFailure = isA<SiteLookupException>().having(
  (error) => error.cause,
  'cause',
  isA<TimeoutException>(),
);

class _Result<T> {
  _Result(Future<T> future) {
    unawaited(
      future.then<void>(
        (result) {
          value = result;
          done = true;
        },
        onError: (Object failure, StackTrace stack) {
          error = failure;
          done = true;
        },
      ),
    );
  }
  T? value;
  Object? error;
  bool done = false;
}

class _HeldClient extends http.BaseClient {
  final reads = <_HeldRead>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final read = _HeldRead(request);
    reads.add(read);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.then((_) {
          read.aborted = true;
          if (!read.headers.isCompleted) {
            read.headers.completeError(
              http.RequestAbortedException(request.url),
            );
          }
        }),
      );
    }
    return read.headers.future;
  }
}

class _HeldRead {
  _HeldRead(this.request);
  final http.BaseRequest request;
  final headers = Completer<http.StreamedResponse>();
  bool aborted = false;
  void respond() => headers.complete(
    http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    ),
  );
}
