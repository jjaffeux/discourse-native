import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_read_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const siteUrl = 'https://forum.example';
  late Completer<http.Response> firstResponse;
  late List<http.Request> requests;
  late Set<int> confirmedPosts;
  late _CountingCredentials credentials;
  late Map<int, int> responseStatuses;
  late Store store;
  late TopicReadController controller;
  late List<Object> errors;
  late int activeRequests;
  late int maximumActiveRequests;

  setUp(() {
    firstResponse = Completer();
    requests = [];
    confirmedPosts = {};
    credentials = _CountingCredentials()..keys[siteUrl] = 'key';
    responseStatuses = {};
    store = Store()
      ..put(
        siteUrl,
        const Topic(
          id: 1,
          title: 'Topic',
          slug: 'topic',
          lastReadPostNumber: 0,
          highestPostNumber: 1000,
          unreadPosts: 1000,
        ),
      );
    errors = [];
    activeRequests = 0;
    maximumActiveRequests = 0;
    final api = DiscourseApi(
      client: MockClient((request) async {
        requests.add(request);
        activeRequests++;
        if (activeRequests > maximumActiveRequests) {
          maximumActiveRequests = activeRequests;
        }
        try {
          final response = requests.length == 1
              ? await firstResponse.future
              : http.Response('', responseStatuses[requests.length] ?? 200);
          if (response.statusCode == 200) {
            // The server's Notification.mark_posts_read matches exactly these
            // post numbers, independently of TopicUser's maximum read position.
            confirmedPosts.addAll(_timings(request).keys.map(int.parse));
          }
          return response;
        } finally {
          activeRequests--;
        }
      }),
    );
    addTearDown(api.close);
    controller = TopicReadController(
      api: api,
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      store: store,
      reportError: (error, _, _) => errors.add(error),
    );
  });

  tearDown(() {
    controller.dispose();
    if (!firstResponse.isCompleted) {
      firstResponse.complete(http.Response('', 200));
    }
  });

  test('delivers every admitted post through the timings transport', () async {
    final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
    await pumpEventQueue();
    final second = controller.mark(siteUrl, 1, 2, caughtUp: false);
    final third = controller.mark(siteUrl, 1, 3, caughtUp: false);
    await pumpEventQueue();

    expect(requests, hasLength(1));
    expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 3);
    firstResponse.complete(http.Response('', 200));
    await Future.wait([first, second, third]);

    expect(confirmedPosts, {1, 2, 3});
    expect(requests.map(_timings), [
      {'1': 500},
      {'2': 500, '3': 500},
    ]);
    expect(maximumActiveRequests, 1);
    expect(errors, isEmpty);

    for (final post in [1, 2, 3]) {
      await controller.mark(siteUrl, 1, post, caughtUp: false);
    }
    expect(requests, hasLength(2), reason: 'successful reads are deduplicated');
    for (final request in requests) {
      expect(request.method, 'POST');
      expect(request.url.path, '/topics/timings.json');
      expect(request.headers['User-Api-Key'], 'key');
      expect(request.headers['User-Api-Client-Id'], 'test-client');
    }
    expect(_body(requests.last)['topic_time'], 1000);
  });

  for (final retryPost in [1, 3]) {
    test(
      'a newer successful read preserves failed post 1 for retry at $retryPost',
      () async {
        final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
        await pumpEventQueue();
        final newer = controller.mark(siteUrl, 1, 3, caughtUp: false);
        firstResponse.complete(http.Response('', 503));
        await Future.wait([first, newer]);

        expect(confirmedPosts, {3});
        expect(requests, hasLength(2), reason: 'failure alone must not retry');
        expect(errors, hasLength(1));

        await controller.mark(siteUrl, 1, retryPost, caughtUp: false);

        expect(confirmedPosts, {1, 3});
        expect(requests.map(_timings), [
          {'1': 500},
          {'3': 500},
          {'1': 500},
        ]);
        expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 3);
        expect(maximumActiveRequests, 1);
        await controller.mark(siteUrl, 1, retryPost, caughtUp: false);
        expect(requests, hasLength(3));
      },
    );
  }

  test('retains every failed batch through later successful reads', () async {
    responseStatuses[2] = 503;
    final first = controller.mark(siteUrl, 1, 1, caughtUp: false);
    await pumpEventQueue();
    final second = controller.mark(siteUrl, 1, 2, caughtUp: false);
    final third = controller.mark(siteUrl, 1, 3, caughtUp: false);
    firstResponse.complete(http.Response('', 503));
    await Future.wait([first, second, third]);
    expect(confirmedPosts, isEmpty);
    expect(requests, hasLength(2), reason: 'failed batches must not spin');

    await controller.mark(siteUrl, 1, 5, caughtUp: false);

    expect(confirmedPosts, {1, 2, 3, 5});
    expect(_timings(requests.last), {'1': 500, '2': 500, '3': 500, '5': 500});
    expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 5);
    expect(errors, hasLength(2));
    for (final post in [1, 2, 3, 5]) {
      await controller.mark(siteUrl, 1, post, caughtUp: false);
    }
    expect(requests, hasLength(3));
  });

  test(
    'bounds batch sizes while retaining a large queue of exact posts',
    () async {
      const lastPost = TopicReadsApi.maximumPostsPerRequest * 2 + 5;
      final reads = [controller.mark(siteUrl, 1, 1, caughtUp: false)];
      await pumpEventQueue();
      for (var post = 2; post <= lastPost; post++) {
        reads.add(controller.mark(siteUrl, 1, post, caughtUp: false));
        reads.add(controller.mark(siteUrl, 1, post, caughtUp: false));
      }
      expect(requests, hasLength(1));
      firstResponse.complete(http.Response('', 200));
      await Future.wait(reads);

      expect(confirmedPosts, {
        for (var post = 1; post <= lastPost; post++) post,
      });
      expect(requests.map((request) => _timings(request).length), [
        1,
        100,
        100,
        4,
      ]);
      expect(maximumActiveRequests, 1);
      expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, lastPost);
    },
  );

  test(
    'missing credentials defer all admitted posts without spinning',
    () async {
      credentials.keys.clear();
      final reads = [
        for (var post = 1; post <= 205; post++)
          controller.mark(siteUrl, 1, post, caughtUp: false),
      ];
      await Future.wait(reads);
      await pumpEventQueue();
      expect(requests, isEmpty);
      expect(credentials.lookups, 1);

      await controller.mark(siteUrl, 1, 205, caughtUp: false);
      await pumpEventQueue();
      expect(credentials.lookups, 2);
      expect(requests, isEmpty);
      expect(errors, isEmpty);

      credentials.keys[siteUrl] = 'restored-key';
      firstResponse.complete(http.Response('', 200));
      await controller.mark(siteUrl, 1, 205, caughtUp: false);

      expect(confirmedPosts, {for (var post = 1; post <= 205; post++) post});
      expect(requests.map((request) => _timings(request).length), [
        100,
        100,
        5,
      ]);
      expect(requests.first.headers['User-Api-Key'], 'restored-key');
      expect(store.read<Topic>(siteUrl, 1)?.lastReadPostNumber, 205);
    },
  );
}

final class _CountingCredentials extends FakeApiCredentialReader {
  int lookups = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    lookups++;
    return super.apiKeyFor(siteUrl);
  }
}

Map<String, dynamic> _body(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

Map<String, dynamic> _timings(http.Request request) =>
    _body(request)['timings'] as Map<String, dynamic>;
