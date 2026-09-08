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
    required this.postNumbers,
  });

  final String siteUrl;
  final String apiKey;
  final String? clientId;
  final int topicId;
  final List<int> postNumbers;
  final Completer<void> response = Completer();
}

final class _ControlledTopicReadsApi implements TopicReadsApi {
  final List<_PendingRead> requests = [];

  @override
  Future<void> recordTopicReads({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postNumbers,
    int milliseconds = 500,
    String? clientId,
  }) {
    final request = _PendingRead(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      topicId: topicId,
      postNumbers: postNumbers,
    );
    requests.add(request);
    return request.response.future;
  }
}

Map<String, Object?> _requestSnapshot(_PendingRead request) => {
  'siteUrl': request.siteUrl,
  'apiKey': request.apiKey,
  'clientId': request.clientId,
  'topicId': request.topicId,
  'postNumbers': request.postNumbers,
};

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
          {
            'siteUrl': siteUrl,
            'apiKey': 'key',
            'clientId': 'test-client',
            'topicId': 1,
            'postNumbers': [5],
          },
          {
            'siteUrl': siteUrl,
            'apiKey': 'key',
            'clientId': 'test-client',
            'topicId': 1,
            'postNumbers': [10],
          },
        ]);
      },
    );

    test('a caught-up duplicate clears the optimistic unread state', () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      store.put(siteUrl, _topic(highest: 12));

      final partial = controller.mark(siteUrl, 1, 12, caughtUp: false);
      await pumpEventQueue();

      expect(store.read<Topic>(siteUrl, 1)!.hasUnread, isTrue);
      api.requests.single.response.complete();
      await partial;

      await controller.mark(siteUrl, 1, 12, caughtUp: true);

      expect(api.requests, hasLength(1));
      expect(store.read<Topic>(siteUrl, 1)!.hasUnread, isFalse);
    });
  });

  group('receipt coalescing and write outcomes', () {
    test(
      'an older caught-up retry preserves the maximum across stale rows',
      () async {
        const siteUrl = 'https://one.example';
        credentials.keys[siteUrl] = 'key';
        store.put(siteUrl, _topic());
        final failed = controller.mark(siteUrl, 1, 5, caughtUp: false);
        await pumpEventQueue();
        final newer = controller.mark(siteUrl, 1, 10, caughtUp: false);
        api.requests.single.response.completeError(StateError('offline'));
        await pumpEventQueue();
        api.requests.last.response.complete();
        await Future.wait([failed, newer]);

        store.put(siteUrl, _topic(lastRead: 4, highest: 5));
        final retry = controller.mark(siteUrl, 1, 5, caughtUp: true);
        expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 10);
        await pumpEventQueue();
        expect(api.requests.last.postNumbers, [5]);
        api.requests.last.response.complete();
        await retry;

        await controller.mark(siteUrl, 1, 5, caughtUp: true);
        expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 10);
        expect(api.requests, hasLength(3));
      },
    );

    test(
      'a failed position can be retried when it is observed again',
      () async {
        const siteUrl = 'https://one.example';
        credentials.keys[siteUrl] = 'key';
        store.put(siteUrl, _topic(highest: 5));
        addTearDown(() {
          for (final request in api.requests) {
            if (!request.response.isCompleted) request.response.complete();
          }
        });

        final first = controller.mark(siteUrl, 1, 5, caughtUp: true);
        await pumpEventQueue();
        api.requests.single.response.completeError(StateError('offline'));
        await first;
        expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 5);
        expect(
          api.requests,
          hasLength(1),
          reason: 'failure alone must not retry',
        );

        await controller.mark(siteUrl, 1, 4, caughtUp: false);
        expect(api.requests, hasLength(1));
        final retry = controller.mark(siteUrl, 1, 5, caughtUp: true);
        await pumpEventQueue();
        expect(api.requests.map((request) => request.postNumbers), [
          [5],
          [5],
        ]);
        api.requests.last.response.complete();
        await retry;

        await controller.mark(siteUrl, 1, 5, caughtUp: true);
        expect(
          api.requests,
          hasLength(2),
          reason: 'a successful retry is deduplicated',
        );
        expect(store.read<Topic>(siteUrl, 1)?.hasUnread, isFalse);
      },
    );

    test('a newer queued read preserves a failed receipt for retry', () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      store.put(siteUrl, _topic());
      final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
      await pumpEventQueue();
      final newer = controller.mark(siteUrl, 1, 5, caughtUp: false);
      api.requests.first.response.completeError(StateError('offline'));
      await pumpEventQueue();
      final retry = controller.mark(siteUrl, 1, 1, caughtUp: false);
      api.requests.last.response.complete();
      await pumpEventQueue();

      expect(api.requests.map((request) => request.postNumbers), [
        [1],
        [5],
        [1],
      ]);
      api.requests.last.response.complete();
      await Future.wait([first, newer, retry]);
      expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 5);
    });

    for (final forget in [false, true]) {
      test(
        'a newer server position only drops failed receipts after forget $forget',
        () async {
          const siteUrl = 'https://one.example';
          credentials.keys[siteUrl] = 'key';
          store.put(siteUrl, _topic());
          final first = controller.mark(siteUrl, 1, 5, caughtUp: false);
          await pumpEventQueue();
          api.requests.single.response.completeError(StateError('offline'));
          await first;

          if (forget) {
            lifecycle.invalidate(siteUrl);
            controller.forget(siteUrl);
            store.put(siteUrl, _topic(lastRead: 5));
          } else {
            store.put(siteUrl, _topic(lastRead: 8));
          }
          final retry = controller.mark(siteUrl, 1, 5, caughtUp: false);
          await pumpEventQueue();

          expect(api.requests, hasLength(forget ? 1 : 2));
          if (!forget) api.requests.last.response.complete();
          await retry;
          expect(
            store.read<Topic>(siteUrl, 1)?.lastReadPostNumber,
            forget ? 5 : 8,
          );
        },
      );
    }

    test(
      'a store listener preserves both the older and newer receipt',
      () async {
        const siteUrl = 'https://one.example';
        credentials.keys[siteUrl] = 'key';
        store.put(siteUrl, _topic());
        var advanced = false;
        Future<void>? newer;
        final ref = store.ref<Topic>(siteUrl, 1);
        void advance() {
          if (advanced) return;
          advanced = true;
          newer = controller.mark(siteUrl, 1, 3, caughtUp: false);
        }

        ref.addListener(advance);
        addTearDown(() {
          ref.removeListener(advance);
          for (final request in api.requests) {
            if (!request.response.isCompleted) request.response.complete();
          }
        });

        final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
        await pumpEventQueue();
        api.requests.single.response.complete();
        await pumpEventQueue();

        expect(
          [for (final request in api.requests) request.postNumbers],
          [
            [1, 3],
          ],
        );
        await Future.wait([first, newer!]);
        expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 3);
      },
    );

    test('batches every position queued behind an active write', () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      store.put(siteUrl, _topic());

      final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
      await pumpEventQueue();
      final second = controller.mark(siteUrl, 1, 2, caughtUp: false);
      final newest = controller.mark(siteUrl, 1, 3, caughtUp: false);
      await pumpEventQueue();

      expect(
        [for (final request in api.requests) request.postNumbers],
        [
          [1],
        ],
      );

      api.requests.first.response.complete();
      await pumpEventQueue();
      expect(
        [for (final request in api.requests) request.postNumbers],
        [
          [1],
          [2, 3],
        ],
      );

      api.requests.last.response.complete();
      await Future.wait([first, second, newest]);
      expect(api.requests.map(_requestSnapshot), [
        {
          'siteUrl': siteUrl,
          'apiKey': 'key',
          'clientId': 'test-client',
          'topicId': 1,
          'postNumbers': [1],
        },
        {
          'siteUrl': siteUrl,
          'apiKey': 'key',
          'clientId': 'test-client',
          'topicId': 1,
          'postNumbers': [2, 3],
        },
      ]);
      expect(errors, isEmpty);
    });

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
          [for (final request in api.requests) request.postNumbers],
          [
            [1],
            [4],
          ],
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
    test('a late failure cannot restore a forgotten account batch', () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'old-key';
      store.put(siteUrl, _topic());
      final retired = controller.mark(siteUrl, 1, 1, caughtUp: false);
      await pumpEventQueue();
      final oldQueued = [
        controller.mark(siteUrl, 1, 2, caughtUp: false),
        controller.mark(siteUrl, 1, 3, caughtUp: false),
      ];

      lifecycle.invalidate(siteUrl);
      controller.forget(siteUrl);
      credentials.keys[siteUrl] = 'new-key';
      store.put(siteUrl, _topic());
      final replacement = controller.mark(siteUrl, 1, 5, caughtUp: false);
      await pumpEventQueue();
      api.requests.first.response.completeError(StateError('old failure'));
      await Future.wait([retired, ...oldQueued]);
      final newer = controller.mark(siteUrl, 1, 6, caughtUp: false);
      expect(api.requests, hasLength(2));
      api.requests.last.response.complete();
      await pumpEventQueue();

      expect(api.requests.map((request) => request.postNumbers), [
        [1],
        [5],
        [6],
      ]);
      expect(api.requests.map((request) => request.apiKey), [
        'old-key',
        'new-key',
        'new-key',
      ]);
      api.requests.last.response.complete();
      await Future.wait([replacement, newer]);
      await controller.mark(siteUrl, 1, 6, caughtUp: false);
      expect(api.requests, hasLength(3));
      expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 6);
      expect(errors, isEmpty);
    });

    for (final dispose in [false, true]) {
      test(
        'a store listener can cancel admitted receipts with dispose $dispose',
        () async {
          const siteUrl = 'https://one.example';
          credentials.keys[siteUrl] = 'key';
          store.put(siteUrl, _topic());
          final ref = store.ref<Topic>(siteUrl, 1);
          void cancel() =>
              dispose ? controller.dispose() : controller.forget(siteUrl);
          ref.addListener(cancel);
          addTearDown(() => ref.removeListener(cancel));

          await controller.mark(siteUrl, 1, 1, caughtUp: false);
          expect(api.requests, isEmpty);
          expect(errors, isEmpty);
        },
      );
    }

    test(
      'a store listener can replace the account without losing its queued receipt',
      () async {
        const siteUrl = 'https://one.example';
        credentials.keys[siteUrl] = 'old-key';
        store.put(siteUrl, _topic());
        var replaced = false;
        final replacementReads = <Future<void>>[];
        final ref = store.ref<Topic>(siteUrl, 1);
        void replaceAccount() {
          if (replaced) return;
          replaced = true;
          lifecycle.invalidate(siteUrl);
          controller.forget(siteUrl);
          credentials.keys[siteUrl] = 'new-key';
          store.put(siteUrl, _topic());
          replacementReads.add(controller.mark(siteUrl, 1, 2, caughtUp: false));
          replacementReads.add(controller.mark(siteUrl, 1, 3, caughtUp: false));
        }

        ref.addListener(replaceAccount);
        addTearDown(() {
          ref.removeListener(replaceAccount);
          for (final request in api.requests) {
            if (!request.response.isCompleted) request.response.complete();
          }
        });

        final retired = controller.mark(siteUrl, 1, 5, caughtUp: false);
        await pumpEventQueue();
        api.requests.single.response.complete();
        await pumpEventQueue();

        expect(
          [
            for (final request in api.requests)
              (request.apiKey, request.postNumbers.single),
          ],
          [('new-key', 2), ('new-key', 3)],
        );
        api.requests.last.response.complete();
        await Future.wait([retired, ...replacementReads]);
        expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 3);
      },
    );

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
          [for (final request in api.requests) request.postNumbers],
          [
            [1],
            [2],
          ],
        );

        api.requests.last.response.complete();
        await Future.wait([first, newer]);
        expect(api.requests.map(_requestSnapshot), [
          {
            'siteUrl': retained,
            'apiKey': 'key',
            'clientId': 'test-client',
            'topicId': 1,
            'postNumbers': [1],
          },
          {
            'siteUrl': retained,
            'apiKey': 'key',
            'clientId': 'test-client',
            'topicId': 1,
            'postNumbers': [2],
          },
        ]);
        expect(errors, isEmpty);
      },
    );
  });

  group('disposal', () {
    test('drops queued batches and ignores a late failed request', () async {
      const siteUrl = 'https://one.example';
      credentials.keys[siteUrl] = 'key';
      store.put(siteUrl, _topic());
      final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
      await pumpEventQueue();
      final queued = [
        controller.mark(siteUrl, 1, 2, caughtUp: false),
        controller.mark(siteUrl, 1, 3, caughtUp: false),
      ];
      controller.dispose();
      api.requests.single.response.completeError(StateError('late failure'));
      await Future.wait([first, ...queued]);

      expect(api.requests, hasLength(1));
      expect(errors, isEmpty);
    });

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
