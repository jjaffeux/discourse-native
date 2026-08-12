import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_read_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

final class _PendingRead {
  _PendingRead({
    required this.siteUrl,
    required this.apiKey,
    required this.clientId,
    required this.topicId,
    required this.postNumber,
  });

  final String siteUrl;
  final String apiKey;
  final String? clientId;
  final int topicId;
  final int postNumber;
  final Completer<void> response = Completer();
}

final class _ControlledTopicReadsApi implements TopicReadsApi {
  final List<_PendingRead> requests = [];

  @override
  Future<void> recordTopicRead({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postNumber,
    int milliseconds = 500,
    String? clientId,
  }) {
    final request = _PendingRead(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      topicId: topicId,
      postNumber: postNumber,
    );
    requests.add(request);
    return request.response.future;
  }
}

final class _GatedClientIdReader implements ApiCredentialReader {
  final Completer<void> clientIdStarted = Completer();
  final Completer<String> clientIdResult = Completer();

  @override
  Future<String?> apiKeyFor(String siteUrl) async => 'old-key';

  @override
  Future<String> clientId() {
    clientIdStarted.complete();
    return clientIdResult.future;
  }
}

Topic _topic({int id = 1, int lastRead = 0, int highest = 10}) => Topic(
  id: id,
  title: 'Topic $id',
  slug: 'topic-$id',
  unreadPosts: highest - lastRead,
  lastReadPostNumber: lastRead,
  highestPostNumber: highest,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ControlledTopicReadsApi api;
  late FakeApiCredentialReader credentials;
  late SiteLifecycle lifecycle;
  late Store store;
  late List<({Object error, String operation})> errors;
  late TopicReadController controller;

  setUp(() {
    api = _ControlledTopicReadsApi();
    credentials = FakeApiCredentialReader();
    lifecycle = SiteLifecycle();
    store = Store();
    errors = [];
    controller = TopicReadController(
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      store: store,
      reportError: (error, _, operation) {
        errors.add((error: error, operation: operation));
      },
    );
  });

  tearDown(() => controller.dispose());

  test(
    'invalid topic coordinates are ignored without mutating shared state',
    () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      store.put(siteUrl, _topic());

      await controller.mark(siteUrl, 0, 1, caughtUp: true);
      await controller.mark(siteUrl, 1, 0, caughtUp: true);

      expect(api.requests, isEmpty);
      expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 0);
    },
  );

  test(
    'updates the shared topic optimistically without clearing newer unread',
    () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      store.put(siteUrl, _topic());

      final first = controller.mark(siteUrl, 1, 5, caughtUp: true);
      await pumpEventQueue();

      expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 5);
      expect(store.read<Topic>(siteUrl, 1)?.hasUnread, isTrue);

      api.requests.single.response.complete();
      await first;

      final caughtUp = controller.mark(siteUrl, 1, 10, caughtUp: true);
      await pumpEventQueue();
      expect(store.read<Topic>(siteUrl, 1)?.hasUnread, isFalse);
      api.requests.last.response.complete();
      await caughtUp;
    },
  );

  test(
    'serializes a topic and sends only its newest queued position',
    () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      store.put(siteUrl, _topic());

      final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
      await pumpEventQueue();
      final second = controller.mark(siteUrl, 1, 2, caughtUp: false);
      final newest = controller.mark(siteUrl, 1, 3, caughtUp: false);
      await pumpEventQueue();

      expect([for (final request in api.requests) request.postNumber], [1]);

      api.requests.first.response.complete();
      await pumpEventQueue();
      expect([for (final request in api.requests) request.postNumber], [1, 3]);

      api.requests.last.response.complete();
      await Future.wait([first, second, newest]);
      expect(api.requests.last.clientId, 'test-client');
    },
  );

  test(
    'a failed receipt is reported and still drains the newer position',
    () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      store.put(siteUrl, _topic());

      final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
      await pumpEventQueue();
      final newer = controller.mark(siteUrl, 1, 4, caughtUp: false);
      api.requests.first.response.completeError(StateError('offline'));
      await pumpEventQueue();

      expect([for (final request in api.requests) request.postNumber], [1, 4]);
      expect(errors, hasLength(1));
      expect(errors.single.operation, 'topic.markRead');

      api.requests.last.response.complete();
      await Future.wait([first, newer]);
    },
  );

  test('forget after key lookup prevents the queued request', () async {
    const siteUrl = 'https://one.example';
    final gatedCredentials = _GatedClientIdReader();
    final guarded = TopicReadController(
      api: api,
      credentials: gatedCredentials,
      lifecycle: lifecycle,
      store: store,
      reportError: (error, _, operation) {
        errors.add((error: error, operation: operation));
      },
    );
    addTearDown(guarded.dispose);
    store.put(siteUrl, _topic());

    final read = guarded.mark(siteUrl, 1, 2, caughtUp: false);
    await gatedCredentials.clientIdStarted.future;
    guarded.forget(siteUrl);
    gatedCredentials.clientIdResult.complete('old-client');
    await read;

    expect(api.requests, isEmpty);
    expect(errors, isEmpty);
  });

  test(
    'account invalidation after key lookup prevents stale credentials',
    () async {
      const siteUrl = 'https://one.example';
      final gatedCredentials = _GatedClientIdReader();
      final guarded = TopicReadController(
        api: api,
        credentials: gatedCredentials,
        lifecycle: lifecycle,
        store: store,
        reportError: (error, _, operation) {
          errors.add((error: error, operation: operation));
        },
      );
      addTearDown(guarded.dispose);
      store.put(siteUrl, _topic());

      final read = guarded.mark(siteUrl, 1, 2, caughtUp: false);
      await gatedCredentials.clientIdStarted.future;
      lifecycle.invalidate(siteUrl);
      gatedCredentials.clientIdResult.complete('old-client');
      await read;

      expect(api.requests, isEmpty);
      expect(errors, isEmpty);
    },
  );

  test(
    'forget matches the site exactly and keeps a similar site serialized',
    () async {
      const forgotten = 'https://one.example';
      const retained = 'https://one.example.invalid';
      credentials.keys[retained] = 'key';
      store.put(retained, _topic());

      final first = controller.mark(retained, 1, 1, caughtUp: false);
      await pumpEventQueue();
      controller.forget(forgotten);
      final newer = controller.mark(retained, 1, 2, caughtUp: false);
      await pumpEventQueue();

      expect(api.requests, hasLength(1));
      api.requests.first.response.complete();
      await pumpEventQueue();
      expect([for (final request in api.requests) request.postNumber], [1, 2]);

      api.requests.last.response.complete();
      await Future.wait([first, newer]);
    },
  );

  test(
    'dispose cancels work waiting on credentials and ignores new marks',
    () async {
      const siteUrl = 'https://one.example';
      final gatedCredentials = _GatedClientIdReader();
      final guarded = TopicReadController(
        api: api,
        credentials: gatedCredentials,
        lifecycle: lifecycle,
        store: store,
        reportError: (error, _, operation) {
          errors.add((error: error, operation: operation));
        },
      );
      store.put(siteUrl, _topic());

      final read = guarded.mark(siteUrl, 1, 2, caughtUp: false);
      await gatedCredentials.clientIdStarted.future;
      guarded.dispose();
      gatedCredentials.clientIdResult.complete('old-client');
      await read;
      await guarded.mark(siteUrl, 1, 3, caughtUp: false);

      expect(api.requests, isEmpty);
      expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 2);
    },
  );
}
