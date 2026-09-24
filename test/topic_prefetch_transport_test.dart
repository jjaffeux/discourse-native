import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const site = 'https://example.com';
  final aborted = throwsA(
    isA<SiteLookupException>().having(
      (error) => error.cause,
      'cause',
      isA<http.RequestAbortedException>(),
    ),
  );

  test('a pre-cancelled topic never reaches the client', () async {
    final client = _Client();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final abort = Completer<void>()..complete();
    await expectLater(
      api.topic(
        siteUrl: site,
        slug: 'topic',
        id: 1,
        abortTrigger: abort.future,
      ),
      aborted,
    );
    expect(client.requests, isEmpty);
  });

  test(
    'cancelling a speculative GET leaves an ordinary identical GET alive',
    () async {
      final client = _Client();
      final api = DiscourseApi(client: client);
      addTearDown(api.close);
      final abort = Completer<void>();
      final speculation = api.topic(
        siteUrl: site,
        slug: 'topic',
        id: 1,
        abortTrigger: abort.future,
      );
      final cancelled = expectLater(speculation, aborted);
      await Future<void>.delayed(Duration.zero);
      final navigation = api.topic(siteUrl: site, slug: 'topic', id: 1);
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, hasLength(2));
      abort.complete();
      await cancelled;
      expect(client.requests.last.aborted, isFalse);
      client.requests.last.complete();
      expect((await navigation).detail.id, 1);
    },
  );

  test(
    'cancelling while reading the response body releases its network slot',
    () async {
      final client = _Client();
      final transport = DiscourseTransport(
        SafeHttpClient.owned(client),
        const Duration(seconds: 2),
        1024,
        maxConcurrentPerOrigin: 1,
      );
      final api = DiscourseApi(transport: transport);
      addTearDown(api.close);
      final abort = Completer<void>();
      final first = api.topic(
        siteUrl: site,
        slug: 'topic',
        id: 1,
        abortTrigger: abort.future,
      );
      final cancelled = expectLater(first, aborted);
      await Future<void>.delayed(Duration.zero);
      client.requests.single.sendHeaders();
      client.requests.single.body.add(utf8.encode('{"id":'));
      await Future<void>.delayed(Duration.zero);
      final next = api.topic(siteUrl: site, slug: 'topic', id: 2);
      expect(client.requests, hasLength(1));
      abort.complete();
      await cancelled;
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, hasLength(2));
      client.requests.last.complete();
      await next;
    },
  );

  test(
    'cancelled queued reads are removed before dispatch and free the backlog',
    () async {
      final client = _Client();
      final transport = DiscourseTransport(
        SafeHttpClient.owned(client),
        const Duration(seconds: 2),
        1024,
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 1,
      );
      final api = DiscourseApi(transport: transport);
      addTearDown(api.close);
      final first = api.topic(siteUrl: site, slug: 'topic', id: 1);
      await Future<void>.delayed(Duration.zero);
      final abort = Completer<void>();
      final queued = api.topic(
        siteUrl: site,
        slug: 'topic',
        id: 2,
        abortTrigger: abort.future,
      );
      final cancelled = expectLater(queued, aborted);
      await Future<void>.delayed(Duration.zero);
      abort.complete();
      await cancelled;
      final latest = api.topic(siteUrl: site, slug: 'topic', id: 3);
      client.requests.single.complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(client.requests.map((r) => r.request.url.path), [
        '/t/1.json',
        '/t/3.json',
      ]);
      client.requests.last.complete();
      await latest;
    },
  );
}

class _Client extends http.BaseClient {
  final requests = <_Request>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final pending = _Request(request);
    requests.add(pending);
    return pending.response.future;
  }
}

class _Request {
  _Request(this.request) {
    final abort = (request as http.Abortable).abortTrigger;
    unawaited(
      abort?.then((_) {
        aborted = true;
        final error = http.RequestAbortedException(request.url);
        if (!response.isCompleted) {
          response.completeError(error);
        } else if (!body.isClosed) {
          body.addError(error);
          unawaited(body.close());
        }
      }),
    );
  }
  final http.BaseRequest request;
  final response = Completer<http.StreamedResponse>();
  final body = StreamController<List<int>>();
  bool aborted = false;
  void sendHeaders() =>
      response.complete(http.StreamedResponse(body.stream, 200));
  void complete() {
    sendHeaders();
    body.add(
      utf8.encode(
        '{"id":1,"title":"Topic","post_stream":{"posts":[],"stream":[]}}',
      ),
    );
    unawaited(body.close());
  }
}
