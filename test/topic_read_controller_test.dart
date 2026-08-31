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

({String siteUrl, String apiKey, String? clientId, int topicId, int postNumber})
_requestSnapshot(_PendingRead request) => (
  siteUrl: request.siteUrl,
  apiKey: request.apiKey,
  clientId: request.clientId,
  topicId: request.topicId,
  postNumber: request.postNumber,
);

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

  group('local read projection', () {
    test('ignores invalid coordinates without mutating shared state', () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      final original = _topic();
      store.put(siteUrl, original);

      await controller.mark(siteUrl, 0, 1, caughtUp: true);
      await controller.mark(siteUrl, 1, 0, caughtUp: true);

      expect(api.requests, isEmpty);
      expect(store.read<Topic>(siteUrl, 1), same(original));
    });

    test(
      'advances optimistically without clearing unread state for newer posts',
      () async {
        const siteUrl = 'https://one.example';
        credentials.keys[siteUrl] = 'key';
        store.put(siteUrl, _topic());

        final first = controller.mark(siteUrl, 1, 5, caughtUp: true);
        await pumpEventQueue();

        final partial = store.read<Topic>(siteUrl, 1)!;
        expect(
          (
            lastReadPostNumber: partial.lastReadPostNumber,
            unreadPosts: partial.unreadPosts,
            hasUnread: partial.hasUnread,
          ),
          (lastReadPostNumber: 5, unreadPosts: 10, hasUnread: true),
        );

        api.requests.single.response.complete();
        await first;

        final caughtUp = controller.mark(siteUrl, 1, 10, caughtUp: true);
        await pumpEventQueue();

        final complete = store.read<Topic>(siteUrl, 1)!;
        expect(
          (
            lastReadPostNumber: complete.lastReadPostNumber,
            unreadPosts: complete.unreadPosts,
            hasUnread: complete.hasUnread,
          ),
          (lastReadPostNumber: 10, unreadPosts: 0, hasUnread: false),
        );

        api.requests.last.response.complete();
        await caughtUp;
        expect(api.requests.map(_requestSnapshot), [
          (
            siteUrl: siteUrl,
            apiKey: 'key',
            clientId: 'test-client',
            topicId: 1,
            postNumber: 5,
          ),
          (
            siteUrl: siteUrl,
            apiKey: 'key',
            clientId: 'test-client',
            topicId: 1,
            postNumber: 10,
          ),
        ]);
      },
    );
  });

  group('receipt coalescing and write outcomes', () {
    test(
      'sends only the newest position queued behind an active write',
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
        expect(
          [for (final request in api.requests) request.postNumber],
          [1, 3],
        );

        api.requests.last.response.complete();
        await Future.wait([first, second, newest]);
        expect(api.requests.map(_requestSnapshot), [
          (
            siteUrl: siteUrl,
            apiKey: 'key',
            clientId: 'test-client',
            topicId: 1,
            postNumber: 1,
          ),
          (
            siteUrl: siteUrl,
            apiKey: 'key',
            clientId: 'test-client',
            topicId: 1,
            postNumber: 3,
          ),
        ]);
        expect(errors, isEmpty);
      },
    );

    test(
      'reports a failed write and still sends the newest position',
      () async {
        const siteUrl = 'https://one.example';
        credentials.keys[siteUrl] = 'key';
        store.put(siteUrl, _topic());
        final failure = StateError('offline');

        final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
        await pumpEventQueue();
        final newer = controller.mark(siteUrl, 1, 4, caughtUp: false);
        api.requests.first.response.completeError(failure);
        await pumpEventQueue();

        expect(
          [for (final request in api.requests) request.postNumber],
          [1, 4],
        );
        expect(errors, hasLength(1));
        expect(errors.single.error, same(failure));
        expect(errors.single.operation, 'topic.markRead');

        api.requests.last.response.complete();
        await Future.wait([first, newer]);
      },
    );
  });

  group('site and account invalidation', () {
    test('forget drops work awaiting a late credential response', () async {
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
      addTearDown(() {
        if (!gatedCredentials.clientIdResult.isCompleted) {
          gatedCredentials.clientIdResult.complete('cleanup-client');
        }
      });
      store.put(siteUrl, _topic());

      final read = guarded.mark(siteUrl, 1, 2, caughtUp: false);
      await gatedCredentials.clientIdStarted.future;
      guarded.forget(siteUrl);
      gatedCredentials.clientIdResult.complete('old-client');
      await read;

      expect(api.requests, isEmpty);
      expect(errors, isEmpty);
    });

    test('account invalidation rejects a late credential response', () async {
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
      addTearDown(() {
        if (!gatedCredentials.clientIdResult.isCompleted) {
          gatedCredentials.clientIdResult.complete('cleanup-client');
        }
      });
      store.put(siteUrl, _topic());

      final read = guarded.mark(siteUrl, 1, 2, caughtUp: false);
      await gatedCredentials.clientIdStarted.future;
      lifecycle.invalidate(siteUrl);
      gatedCredentials.clientIdResult.complete('old-client');
      await read;

      expect(api.requests, isEmpty);
      expect(errors, isEmpty);
    });

    test(
      'forget matches the exact site without cancelling similar sites',
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
        expect(
          [for (final request in api.requests) request.postNumber],
          [1, 2],
        );

        api.requests.last.response.complete();
        await Future.wait([first, newer]);
        expect(api.requests.map(_requestSnapshot), [
          (
            siteUrl: retained,
            apiKey: 'key',
            clientId: 'test-client',
            topicId: 1,
            postNumber: 1,
          ),
          (
            siteUrl: retained,
            apiKey: 'key',
            clientId: 'test-client',
            topicId: 1,
            postNumber: 2,
          ),
        ]);
        expect(errors, isEmpty);
      },
    );
  });

  group('disposal', () {
    test('cancels credential waits and ignores later marks', () async {
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
      addTearDown(() {
        if (!gatedCredentials.clientIdResult.isCompleted) {
          gatedCredentials.clientIdResult.complete('cleanup-client');
        }
      });
      store.put(siteUrl, _topic());

      final read = guarded.mark(siteUrl, 1, 2, caughtUp: false);
      await gatedCredentials.clientIdStarted.future;
      guarded.dispose();
      gatedCredentials.clientIdResult.complete('old-client');
      await read;
      await guarded.mark(siteUrl, 1, 3, caughtUp: false);

      expect(api.requests, isEmpty);
      expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 2);
      expect(errors, isEmpty);
    });
  });
}
