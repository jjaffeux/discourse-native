import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/request_intent.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _site = 'https://forum.example';
final _aborted = throwsA(
  isA<SiteLookupException>().having(
    (error) => error.cause,
    'cause',
    isA<http.RequestAbortedException>(),
  ),
);

void main() {
  for (final stage in ['key', 'client']) {
    test(
      'retirement during the $stage read rejects the original credentials',
      () async {
        final lifecycle = SiteLifecycle();
        final reader = _Credentials();
        final gate = Completer<String>();
        if (stage == 'key') {
          reader.keyGate = gate;
        } else {
          reader.clientGate = gate;
        }
        final session = AccountRequestSession(_site, lifecycle.capture(_site));
        final pending = session.credentials(reader);
        final rejected = expectLater(
          pending,
          throwsA(isA<AccountRequestRetiredException>()),
        );
        await pumpEventQueue();
        lifecycle.invalidate(_site);
        final successor = lifecycle.capture(_site);
        gate.complete('replacement-credential');
        await rejected;
        expect(successor.isCurrent, isTrue);
        if (stage == 'key') expect(reader.clientReads, 0);
      },
    );
  }

  test('key-only capture never reads or sends a client ID', () async {
    final fixture = _Fixture();
    addTearDown(fixture.api.close);
    final reader = _Credentials();
    final snapshot = await AccountRequestSession(
      _site,
      fixture.lifecycle.capture(_site),
    ).keyCredentials(reader);
    expect(snapshot.clientId, isEmpty);
    expect(reader.clientReads, 0);
    final pending = snapshot.run(
      () => fixture.api.topic(
        siteUrl: _site,
        slug: '',
        id: 1,
        apiKey: snapshot.apiKey,
      ),
    );
    await pumpEventQueue();
    expect(
      fixture.client.requests.single.request.headers['User-Api-Client-Id'],
      isNull,
    );
    fixture.client.requests.single.complete();
    await pending;
  });

  test('key-only acquisition rejects retirement during storage read', () async {
    final lifecycle = SiteLifecycle();
    final reader = _Credentials()..keyGate = Completer<String>();
    final pending = AccountRequestSession(
      _site,
      lifecycle.capture(_site),
    ).keyCredentials(reader);
    final rejected = expectLater(
      pending,
      throwsA(isA<AccountRequestRetiredException>()),
    );
    await pumpEventQueue();
    lifecycle.invalidate(_site);
    reader.keyGate!.complete('replacement-key');
    await rejected;
    expect(reader.clientReads, 0);
  });

  test(
    'explicit anonymous capture needs no credential reader and retires',
    () async {
      final lifecycle = SiteLifecycle();
      final session = AccountRequestSession(_site, lifecycle.capture(_site));
      final snapshot = session.anonymousCredentials();
      expect(snapshot.apiKey, isNull);
      expect(snapshot.clientId, isEmpty);
      lifecycle.invalidate(_site);
      expect(
        session.anonymousCredentials,
        throwsA(isA<AccountRequestRetiredException>()),
      );
      await expectLater(
        snapshot.run(() async => 1),
        throwsA(isA<AccountRequestRetiredException>()),
      );
    },
  );

  test('anonymous reads never access the client ID', () async {
    final lifecycle = SiteLifecycle();
    final reader = _Credentials()..key = null;
    final snapshot = await AccountRequestSession(
      _site,
      lifecycle.capture(_site),
    ).credentials(reader);
    expect(snapshot.apiKey, isNull);
    expect(snapshot.clientId, isEmpty);
    expect(reader.clientReads, 0);
  });

  test(
    'a captured credential cannot execute under a successor session',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.api.close);
      final snapshot = await fixture.credentials();
      fixture.lifecycle.invalidate(_site);
      var invoked = false;
      await expectLater(
        snapshot.run(() async {
          invoked = true;
        }),
        throwsA(isA<AccountRequestRetiredException>()),
      );
      expect(invoked, isFalse);
      expect(fixture.client.requests, isEmpty);
    },
  );

  test(
    'retiring a queued topic withdraws it and frees the bounded backlog',
    () async {
      final fixture = _Fixture(concurrency: 1, backlog: 1);
      addTearDown(fixture.api.close);
      final active = fixture.api.topic(siteUrl: _site, slug: '', id: 1);
      await pumpEventQueue();
      final snapshot = await fixture.credentials();
      final queued = fixture.topic(snapshot, id: 2);
      final rejected = expectLater(queued, _aborted);
      await pumpEventQueue();
      fixture.lifecycle.invalidate(_site);
      await rejected;
      await pumpEventQueue();
      final successor = await fixture.credentials();
      final next = fixture.topic(successor, id: 3);
      await pumpEventQueue();
      expect(fixture.client.paths, ['/t/1.json']);
      fixture.client.requests.first.complete();
      await active;
      await pumpEventQueue();
      expect(fixture.client.paths, ['/t/1.json', '/t/3.json']);
      fixture.client.requests.last.complete();
      await next;
    },
  );

  for (final cancelStarter in [true, false]) {
    test(
      'cancelling ${cancelStarter ? 'starter' : 'joiner'} keeps a coalesced session waiter alive',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.api.close);
        final snapshot = await fixture.credentials();
        final cancel = Completer<void>();
        final first = fixture.topic(
          snapshot,
          abort: cancelStarter ? cancel.future : null,
        );
        final second = fixture.topic(
          snapshot,
          abort: cancelStarter ? null : cancel.future,
        );
        final rejected = expectLater(cancelStarter ? first : second, _aborted);
        await pumpEventQueue();
        expect(fixture.client.requests, hasLength(1));
        cancel.complete();
        await rejected;
        expect(fixture.client.requests.single.aborted, isFalse);
        fixture.client.requests.single.complete();
        expect((await (cancelStarter ? second : first)).detail.id, 1);
      },
    );
  }

  test(
    'retirement abandons all shared waiters and isolates the successor with the same key',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.api.close);
      final snapshot = await fixture.credentials();
      final first = fixture.topic(snapshot);
      final second = fixture.topic(snapshot);
      final rejected = [
        expectLater(first, _aborted),
        expectLater(second, _aborted),
      ];
      await pumpEventQueue();
      expect(fixture.client.requests, hasLength(1));
      fixture.lifecycle.invalidate(_site);
      final successor = await fixture.credentials();
      final next = fixture.topic(successor);
      await Future.wait(rejected);
      await pumpEventQueue();
      expect(fixture.client.requests, hasLength(2));
      expect(fixture.client.requests.first.aborted, isTrue);
      expect(fixture.client.requests.last.aborted, isFalse);
      fixture.client.requests.last.complete();
      await next;
    },
  );

  test(
    'distinct session generations never share identical credential headers',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.api.close);
      final first = fixture.topic(await fixture.credentials());
      final other = await AccountRequestSession(
        _site,
        SiteLifecycle().capture(_site),
      ).credentials(_Credentials());
      final second = fixture.topic(other);
      await pumpEventQueue();
      expect(fixture.client.requests, hasLength(2));
      for (final request in fixture.client.requests) {
        request.complete();
      }
      await Future.wait([first, second]);
    },
  );

  test(
    'retirement during the response body aborts the last safe reader',
    () async {
      final fixture = _Fixture(concurrency: 1);
      addTearDown(fixture.api.close);
      final first = fixture.topic(await fixture.credentials());
      final rejected = expectLater(first, _aborted);
      await pumpEventQueue();
      fixture.client.requests.single.sendHeaders();
      fixture.client.requests.single.body.add(utf8.encode('{"id":'));
      final next = fixture.api.topic(siteUrl: _site, slug: '', id: 2);
      fixture.lifecycle.invalidate(_site);
      await rejected;
      await pumpEventQueue();
      expect(fixture.client.requests, hasLength(2));
      fixture.client.requests.last.complete();
      await next;
    },
  );

  test('retired queued writes report notSent and never reach HTTP', () async {
    final fixture = _Fixture(concurrency: 1);
    addTearDown(fixture.api.close);
    final active = fixture.api.topic(siteUrl: _site, slug: '', id: 1);
    await pumpEventQueue();
    final snapshot = await fixture.credentials();
    final queued = fixture.write(snapshot);
    final rejected = expectLater(
      queued,
      throwsA(
        isA<WriteException>().having((e) => e.notSent, 'notSent', isTrue),
      ),
    );
    fixture.lifecycle.invalidate(_site);
    await rejected;
    expect(fixture.client.requests, hasLength(1));
    fixture.client.requests.first.complete();
    await active;
  });

  for (final fail in [false, true]) {
    test(
      'a dispatched write ${fail ? 'keeps its unknown result' : 'keeps its response'} after retirement',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.api.close);
        final write = fixture.write(await fixture.credentials());
        final outcome = fail
            ? expectLater(
                write,
                throwsA(
                  isA<WriteException>().having(
                    (e) => e.notSent,
                    'notSent',
                    isFalse,
                  ),
                ),
              )
            : null;
        await pumpEventQueue();
        fixture.lifecycle.invalidate(_site);
        await pumpEventQueue();
        expect(fixture.client.requests.single.aborted, isFalse);
        if (fail) {
          fixture.client.requests.single.response.completeError(
            http.ClientException('Connection lost'),
          );
          await outcome;
        } else {
          fixture.client.requests.single.complete('{"applied":true}');
          expect(await write, {'applied': true});
        }
        expect(fixture.client.requests, hasLength(1));
      },
    );
  }

  test(
    'scope refuses mismatched credentials without exposing secrets',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.api.close);
      final snapshot = await fixture.credentials();
      await expectLater(
        snapshot.run(
          () => fixture.api.topic(
            siteUrl: _site,
            slug: '',
            id: 1,
            apiKey: 'other-secret',
          ),
        ),
        throwsA(
          isA<SiteLookupException>().having(
            (e) => e.cause.toString(),
            'cause',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(fixture.client.requests, isEmpty);
    },
  );
  test('retirement wins a simultaneous origin-slot release', () async {
    final fixture = _Fixture(concurrency: 1);
    addTearDown(fixture.api.close);
    final blocker = Completer<http.Response>();
    final occupied = fixture.transport.coordinator.run(
      Uri.parse(_site),
      () => blocker.future,
    );
    final queued = fixture.topic(await fixture.credentials());
    final rejected = expectLater(queued, _aborted);
    await pumpEventQueue();
    blocker.complete(http.Response('{}', 200));
    fixture.lifecycle.invalidate(_site);
    await occupied;
    await rejected;
    expect(fixture.client.requests, isEmpty);
  });

  test('anonymous session scopes refuse an off-origin destination', () async {
    final fixture = _Fixture();
    addTearDown(fixture.api.close);
    final reader = _Credentials()..key = null;
    final snapshot = await AccountRequestSession(
      _site,
      fixture.lifecycle.capture(_site),
    ).credentials(reader);
    await expectLater(
      snapshot.run(
        () => fixture.transport.get(
          Uri.parse('https://other.example/topic.json'),
          siteUrl: _site,
        ),
      ),
      throwsA(isA<SiteLookupException>()),
    );
    expect(fixture.client.requests, isEmpty);
  });

  test(
    'nonempty migration client IDs stay attached to their captured key',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.api.close);
      final snapshot = await AccountRequestSession(
        _site,
        fixture.lifecycle.capture(_site),
      ).credentials(_Credentials()..client = 'migration-client');
      final pending = fixture.topic(snapshot);
      await pumpEventQueue();
      expect(
        fixture.client.requests.single.request.headers,
        containsPair('User-Api-Client-Id', 'migration-client'),
      );
      fixture.client.requests.single.complete();
      await pending;
    },
  );

  test('queued shared work keeps the first sender request Zone', () async {
    final fixture = _Fixture(concurrency: 1);
    addTearDown(fixture.api.close);
    final marker = Object();
    final observed = <Object?>[];
    fixture.client.onSend = () => observed.add(Zone.current[marker]);
    final blocker = Completer<http.Response>();
    final occupied = fixture.transport.coordinator.run(
      Uri.parse(_site),
      () => blocker.future,
    );
    final snapshot = await fixture.credentials();
    final first = runZoned(
      () => fixture.topic(snapshot),
      zoneValues: {marker: 'first'},
    );
    final second = runZoned(
      () => fixture.topic(snapshot),
      zoneValues: {marker: 'joiner'},
    );
    await pumpEventQueue();
    runZoned(
      () => blocker.complete(http.Response('{}', 200)),
      zoneValues: {marker: 'releaser'},
    );
    await occupied;
    await pumpEventQueue();
    expect(observed, ['first']);
    fixture.client.requests.single.complete();
    await Future.wait([first, second]);
  });
  for (final cancelAll in [false, true]) {
    test(
      'queued shared GET ${cancelAll ? 'withdraws after its last owner leaves' : 'keeps a surviving owner'}',
      () async {
        final fixture = _Fixture(concurrency: 1, backlog: 1);
        addTearDown(fixture.api.close);
        final blocker = Completer<http.Response>();
        final occupied = fixture.transport.coordinator.run(
          Uri.parse(_site),
          () => blocker.future,
        );
        final snapshot = await fixture.credentials();
        final cancelFirst = Completer<void>();
        final cancelSecond = Completer<void>();
        final first = fixture.topic(snapshot, abort: cancelFirst.future);
        final second = fixture.topic(snapshot, abort: cancelSecond.future);
        final firstRejected = expectLater(first, _aborted);
        final secondRejected = cancelAll ? expectLater(second, _aborted) : null;
        await pumpEventQueue();
        cancelFirst.complete();
        await firstRejected;
        late Future<TopicPayload> survivor;
        if (cancelAll) {
          cancelSecond.complete();
          await secondRejected;
          survivor = fixture.topic(snapshot);
        } else {
          survivor = second;
        }
        await pumpEventQueue();
        expect(fixture.client.requests, isEmpty);
        blocker.complete(http.Response('{}', 200));
        await occupied;
        await pumpEventQueue();
        expect(fixture.client.requests, hasLength(1));
        expect(fixture.client.requests.single.aborted, isFalse);
        fixture.client.requests.single.complete();
        await survivor;
      },
    );
  }
  test(
    'a surviving interactive waiter promotes its queued shared session GET',
    () async {
      final fixture = _Fixture(concurrency: 1);
      addTearDown(fixture.api.close);
      final blocker = Completer<http.Response>();
      final occupied = fixture.transport.coordinator.run(
        Uri.parse(_site),
        () => blocker.future,
      );
      final snapshot = await fixture.credentials();
      final background = RequestIntent.background();
      final sibling = background.run(() => fixture.topic(snapshot, id: 2));
      final cancel = Completer<void>();
      final starter = background.run(
        () => fixture.topic(snapshot, abort: cancel.future),
      );
      final rejected = expectLater(starter, _aborted);
      final interactive = fixture.topic(snapshot);
      await pumpEventQueue();
      cancel.complete();
      await rejected;
      blocker.complete(http.Response('{}', 200));
      await occupied;
      await pumpEventQueue();
      expect(fixture.client.paths, ['/t/1.json']);
      expect(background.isInteractive, isFalse);
      fixture.client.requests.single.complete();
      await interactive;
      await pumpEventQueue();
      expect(fixture.client.paths, ['/t/1.json', '/t/2.json']);
      fixture.client.requests.last.complete();
      await sibling;
    },
  );
  test(
    'cancelling an interactive joiner leaves only its background waiter priority',
    () async {
      final fixture = _Fixture(concurrency: 1);
      addTearDown(fixture.api.close);
      final blocker = Completer<http.Response>();
      final occupied = fixture.transport.coordinator.run(
        Uri.parse(_site),
        () => blocker.future,
      );
      final snapshot = await fixture.credentials();
      final background = RequestIntent.background();
      final sibling = background.run(() => fixture.topic(snapshot, id: 2));
      final original = background.run(() => fixture.topic(snapshot));
      final cancel = Completer<void>();
      final interactive = fixture.topic(snapshot, abort: cancel.future);
      final rejected = expectLater(interactive, _aborted);
      await pumpEventQueue();
      cancel.complete();
      await rejected;
      blocker.complete(http.Response('{}', 200));
      await occupied;
      await pumpEventQueue();
      expect(fixture.client.paths, ['/t/2.json']);
      expect(background.isInteractive, isFalse);
      fixture.client.requests.single.complete();
      await sibling;
      await pumpEventQueue();
      expect(fixture.client.paths, ['/t/2.json', '/t/1.json']);
      fixture.client.requests.last.complete();
      await original;
    },
  );
}

class _Credentials implements ApiCredentialReader {
  String? key = 'secret';
  String client = '';
  Completer<String>? keyGate;
  Completer<String>? clientGate;
  int clientReads = 0;
  @override
  Future<String?> apiKeyFor(String siteUrl) async =>
      keyGate == null ? key : await keyGate!.future;
  @override
  Future<String> clientId() async {
    clientReads++;
    return clientGate == null ? client : await clientGate!.future;
  }
}

class _Fixture {
  _Fixture({int concurrency = 4, int backlog = 64}) {
    transport = DiscourseTransport(
      SafeHttpClient.owned(client),
      const Duration(seconds: 5),
      4096,
      maxConcurrentPerOrigin: concurrency,
      maxQueuedPerOrigin: backlog,
    );
    api = DiscourseApi(transport: transport);
  }
  final lifecycle = SiteLifecycle();
  final client = _Client();
  late final DiscourseTransport transport;
  late final DiscourseApi api;
  Future<AccountRequestCredentials> credentials() => AccountRequestSession(
    _site,
    lifecycle.capture(_site),
  ).credentials(_Credentials());
  Future<TopicPayload> topic(
    AccountRequestCredentials snapshot, {
    int id = 1,
    Future<void>? abort,
  }) => snapshot.run(
    () => api.topic(
      siteUrl: _site,
      slug: '',
      id: id,
      apiKey: snapshot.apiKey,
      clientId: snapshot.clientId,
      abortTrigger: abort,
    ),
  );
  Future<Map<String, dynamic>> write(AccountRequestCredentials snapshot) =>
      snapshot.run(
        () => transport.write(
          Uri.parse('$_site/write.json'),
          siteUrl: _site,
          method: 'POST',
          apiKey: snapshot.apiKey!,
          clientId: snapshot.clientId,
          body: const {},
        ),
      );
}

class _Client extends http.BaseClient {
  final requests = <_Request>[];
  void Function()? onSend;
  List<String> get paths =>
      requests.map((request) => request.request.url.path).toList();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    onSend?.call();
    final pending = _Request(request);
    requests.add(pending);
    return pending.response.future;
  }
}

class _Request {
  _Request(this.request) {
    unawaited(
      (request as http.Abortable).abortTrigger?.then((_) {
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
  void complete([String? json]) {
    sendHeaders();
    body.add(
      utf8.encode(
        json ??
            '{"id":1,"title":"Topic","post_stream":{"posts":[],"stream":[]}}',
      ),
    );
    unawaited(body.close());
  }
}
