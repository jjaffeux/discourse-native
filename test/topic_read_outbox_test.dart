import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_request_coordinator.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/topic_read_outbox.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_read_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/manual_scheduler.dart';

const _site = 'https://forum.example';
const _offline = WriteException(WriteFailure.unreachable, notSent: true);

final class _Read {
  _Read(this.topicId, this.postNumbers);

  final int topicId;
  final List<int> postNumbers;
  final response = Completer<void>();
}

final class _ReadsApi implements TopicReadsApi {
  final requests = <_Read>[];

  @override
  Future<void> recordTopicReads({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postNumbers,
    int milliseconds = 500,
    String? clientId,
  }) {
    final request = _Read(topicId, postNumbers);
    requests.add(request);
    return request.response.future;
  }

  List<List<int>> get sent => [
    for (final request in requests) request.postNumbers,
  ];
}

/// One launch of the app: its own account session, records and requests, over
/// the file every launch shares.
final class _Launch {
  _Launch(
    this.file, {
    this.account = 'user:sam',
    this.scheduler,
    Duration Function()? elapsed,
  }) : outbox = createTopicReadOutbox(() => file) {
    credentials.keys[_site] = 'key';
    for (final id in [1, 2]) {
      store.put(
        _site,
        Topic(
          id: id,
          title: 'Topic $id',
          slug: 'topic-$id',
          lastReadPostNumber: 0,
          highestPostNumber: 500,
          unreadPosts: 500,
        ),
      );
    }
    final scheduler = this.scheduler;
    controller = TopicReadController(
      api: api,
      credentials: credentials,
      lifecycle: lifecycle,
      store: store,
      outbox: outbox,
      accountFor: (_) => account,
      originSuccesses: (observer) {
        answered = observer;
        return () => answered = null;
      },
      elapsed: elapsed,
      cooldownFactory: scheduler == null
          ? null
          : () => OriginCooldown(
              clock: scheduler.now,
              timerFactory: scheduler.createTimer,
            ),
      confirmedSaveDelay: Duration.zero,
    );
  }

  final File file;
  final api = _ReadsApi();
  final credentials = FakeApiCredentialReader();
  final lifecycle = SiteLifecycle();
  final store = Store();
  final TopicReadOutbox outbox;
  final ManualScheduler? scheduler;
  String? account;
  void Function(String origin)? answered;
  late final TopicReadController controller;

  /// File operations commit in call order, so one issued now completes after
  /// every one the controller has already issued.
  Future<void> settled() async {
    for (var round = 0; round < 3; round++) {
      await outbox.sites();
      await pumpEventQueue();
    }
  }

  /// The file as the next launch would find it.
  Future<PendingTopicReads?> held([String account = 'user:sam']) async {
    await settled();
    if (!await file.exists()) return null;
    final document = jsonDecode(await file.readAsString());
    final section = ((document as Map)['sites'] as Map)[_site];
    if (section is! Map || section['account'] != account) return null;
    return outbox.codec.decode(section['entries']);
  }
}

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('topic-read-outbox-');
    file = File('${directory.path}/topic-reads.json');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  _Launch launch({
    String? account = 'user:sam',
    ManualScheduler? scheduler,
    Duration Function()? elapsed,
  }) {
    final launched = _Launch(
      file,
      account: account,
      scheduler: scheduler,
      elapsed: elapsed,
    );
    addTearDown(launched.controller.dispose);
    return launched;
  }

  /// Leaves posts 1 to 3 of topic 1 unconfirmed, as a session that read them
  /// with the site unreachable does.
  Future<void> leaveUnconfirmedReads() async {
    final first = launch();
    final receipt = first.controller.mark(
      _site,
      1,
      3,
      caughtUp: false,
      readPostNumbers: [1, 2],
    );
    await pumpEventQueue();
    first.api.requests.single.response.completeError(_offline);
    await receipt;
    await first.settled();
    first.controller.dispose();
  }

  test('failed timings survive a restart and are flushed once', () async {
    await leaveUnconfirmedReads();

    final second = launch();
    expect(await second.held(), {
      1: [1, 2, 3],
    });
    final flush = second.controller.flush(_site);
    await second.settled();
    expect(second.api.sent, [
      [1, 2, 3],
    ]);
    second.api.requests.single.response.complete();
    await flush;

    await second.controller.flush(_site);
    second.answered!(_site);
    await second.settled();
    expect(second.api.requests, hasLength(1));
    expect(await second.held(), isNull);

    final third = launch();
    await third.controller.flush(_site);
    expect(third.api.requests, isEmpty);
  });

  test('a batch on the wire when the app is killed is offered again', () async {
    final first = launch();
    unawaited(first.controller.mark(_site, 1, 1, caughtUp: false));
    await first.settled();
    expect(first.api.requests, hasLength(1));

    final second = launch();
    final flush = second.controller.flush(_site);
    await second.settled();
    expect(second.api.sent, [
      [1],
    ]);
    second.api.requests.single.response.complete();
    await flush;
  });

  test('a confirmed timing leaves the file', () async {
    final first = launch();
    final receipt = first.controller.mark(_site, 1, 2, caughtUp: false);
    await first.settled();
    expect(await first.held(), {
      1: [2],
    });
    first.api.requests.single.response.complete();
    await receipt;

    expect(await first.held(), isNull);
  });

  test(
    'a flush during a rate-limit wait sends nothing until it ends',
    () async {
      final scheduler = ManualScheduler();
      final first = launch(scheduler: scheduler);
      final receipt = first.controller.mark(_site, 1, 1, caughtUp: false);
      await pumpEventQueue();
      first.api.requests.single.response.completeError(
        const WriteException(
          WriteFailure.rateLimited,
          statusCode: 429,
          retryAfter: Duration(seconds: 30),
        ),
      );
      await receipt;

      await first.controller.flush(_site);
      first.answered!(_site);
      scheduler.advance(const Duration(seconds: 29));
      await first.settled();
      expect(first.api.requests, hasLength(1));

      scheduler.advance(const Duration(seconds: 1));
      await first.settled();
      expect(first.api.sent, [
        [1],
        [1],
      ]);
      first.api.requests.last.response.complete();
      await first.settled();
      expect(await first.held(), isNull);
    },
  );

  test(
    'a flush waits out the origin cooldown at the request coordinator',
    () async {
      await leaveUnconfirmedReads();
      final scheduler = ManualScheduler();
      OriginCooldown cooldown() => OriginCooldown(
        clock: scheduler.now,
        timerFactory: scheduler.createTimer,
      );
      final sends = <http.Request>[];
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((request) async {
            sends.add(request);
            return http.Response('', 200);
          }),
        ),
        const Duration(seconds: 1),
        1024,
        coordinator: DiscourseRequestCoordinator(
          defaultRateLimitCooldown: const Duration(seconds: 40),
          cooldownFactory: cooldown,
        ),
      );
      addTearDown(transport.close);
      final credentials = FakeApiCredentialReader()..keys[_site] = 'key';
      final outbox = createTopicReadOutbox(() => file);
      final controller = TopicReadController(
        api: DiscourseApi(transport: transport),
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        store: Store(),
        outbox: outbox,
        accountFor: (_) => 'user:sam',
        cooldownFactory: cooldown,
      );
      addTearDown(controller.dispose);
      await transport.coordinator.run(
        Uri.parse('$_site/busy'),
        () async => http.Response('', 429),
      );

      final flush = controller.flush(_site);
      for (var round = 0; round < 3; round++) {
        await outbox.sites();
        await pumpEventQueue();
      }
      scheduler.advance(const Duration(seconds: 39));
      await pumpEventQueue();
      expect(sends, isEmpty, reason: 'the origin asked to be left alone');

      scheduler.advance(const Duration(seconds: 1));
      await flush;
      expect(sends, hasLength(1));
      expect(sends.last.url.path, '/topics/timings.json');
      expect((jsonDecode(sends.last.body) as Map)['timings'], {
        '1': 500,
        '2': 500,
        '3': 500,
      });
    },
  );

  test(
    'a site that answers again is flushed, no more than once an interval',
    () async {
      await leaveUnconfirmedReads();
      var elapsed = Duration.zero;
      final second = launch(elapsed: () => elapsed);
      await second.settled();

      second.answered!('https://elsewhere.example');
      await second.settled();
      expect(second.api.requests, isEmpty);

      second.answered!(_site);
      await second.settled();
      expect(second.api.sent, [
        [1, 2, 3],
      ]);
      second.api.requests.single.response.completeError(_offline);
      await second.settled();

      second.answered!(_site);
      await second.settled();
      expect(second.api.requests, hasLength(1));

      elapsed += TopicReadController.answeredFlushInterval;
      second.answered!(_site);
      await second.settled();
      expect(second.api.sent, [
        [1, 2, 3],
        [1, 2, 3],
      ]);
      second.api.requests.last.response.complete();
      await second.settled();
      expect(await second.held(), isNull);
    },
  );

  test('a flush stops at the first topic the site does not take', () async {
    final first = launch();
    for (final topicId in [1, 2]) {
      final receipt = first.controller.mark(_site, topicId, 1, caughtUp: false);
      await pumpEventQueue();
      first.api.requests.last.response.completeError(_offline);
      await receipt;
    }

    final flush = first.controller.flush(_site);
    await first.settled();
    expect(first.api.requests, hasLength(3));
    first.api.requests.last.response.completeError(_offline);
    await flush;

    expect(first.api.requests, hasLength(3));
    expect(await first.held(), {
      1: [1],
      2: [1],
    });
  });

  test('a topic the site fails on does not hold back the next', () async {
    final first = launch();
    for (final topicId in [1, 2]) {
      final receipt = first.controller.mark(_site, topicId, 1, caughtUp: false);
      await pumpEventQueue();
      first.api.requests.last.response.completeError(_offline);
      await receipt;
    }

    final flush = first.controller.flush(_site);
    await first.settled();
    first.api.requests.last.response.completeError(
      const WriteException(WriteFailure.unreachable, statusCode: 500),
    );
    await first.settled();
    expect(first.api.requests.last.topicId, 2);
    first.api.requests.last.response.complete();
    await flush;

    expect(await first.held(), {
      1: [1],
    });
  });

  test('a refusal the site would repeat is not kept', () async {
    final first = launch();
    final receipt = first.controller.mark(_site, 1, 1, caughtUp: false);
    await pumpEventQueue();
    first.api.requests.single.response.completeError(
      const WriteException(WriteFailure.unreachable, statusCode: 404),
    );
    await receipt;

    expect(await first.held(), isNull);
    await first.controller.flush(_site);
    expect(first.api.requests, hasLength(1));
  });

  test('sign-out or site removal clears the queue', () async {
    await leaveUnconfirmedReads();
    final second = launch();
    unawaited(second.controller.flush(_site));
    await second.settled();
    expect(second.api.requests, hasLength(1));

    second.controller.forget(_site);
    await second.settled();
    expect(await second.outbox.sites(), isEmpty);

    await second.controller.flush(_site);
    second.answered!(_site);
    await second.settled();
    expect(second.api.requests, hasLength(1));
  });

  test('an account change clears the queue', () async {
    await leaveUnconfirmedReads();
    final second = launch();
    await second.settled();

    second.lifecycle.invalidate(_site);
    second.account = 'user:kris';
    await second.controller.flush(_site);
    await second.settled();

    expect(second.api.requests, isEmpty);
    expect(await second.outbox.sites(), isEmpty);
  });

  test('a session that rotates for the same account keeps the queue', () async {
    await leaveUnconfirmedReads();
    final second = launch();
    unawaited(second.controller.flush(_site));
    await second.settled();
    second.api.requests.single.response.completeError(_offline);
    await second.settled();

    second.lifecycle.invalidate(_site);
    await second.settled();
    expect(await second.held(), {
      1: [1, 2, 3],
    });

    final flush = second.controller.flush(_site);
    await second.settled();
    expect(second.api.sent.last, [1, 2, 3]);
    second.api.requests.last.response.complete();
    await flush;
    expect(await second.held(), isNull);
  });

  test("another account's timings are dropped, not sent", () async {
    await leaveUnconfirmedReads();

    final second = launch(account: 'user:kris');
    await second.controller.flush(_site);
    await second.settled();

    expect(second.api.requests, isEmpty);
    expect(await second.outbox.sites(), isEmpty);
  });

  test('a signed-out site sends nothing and keeps the file', () async {
    await leaveUnconfirmedReads();

    final second = launch(account: null);
    await second.controller.flush(_site);
    second.answered!(_site);
    await second.settled();

    expect(second.api.requests, isEmpty);
    expect(await second.held(), {
      1: [1, 2, 3],
    });
  });

  group('ordering', () {
    test('a read that outruns the restore sends each post once', () async {
      await leaveUnconfirmedReads();
      final second = launch();

      final flush = second.controller.flush(_site);
      final receipt = second.controller.mark(
        _site,
        1,
        4,
        caughtUp: false,
        readPostNumbers: [1, 2, 3],
      );
      await second.settled();
      expect(second.api.sent, [
        [1, 2, 3, 4],
      ]);
      second.api.requests.single.response.complete();
      await Future.wait([flush, receipt]);
      await second.controller.flush(_site);

      expect(second.api.requests, hasLength(1));
      expect(await second.held(), isNull);
    });

    test('a read during a flush waits in the topic lane', () async {
      await leaveUnconfirmedReads();
      final second = launch();
      final flush = second.controller.flush(_site);
      await second.settled();
      expect(second.api.sent, [
        [1, 2, 3],
      ]);

      final receipt = second.controller.mark(_site, 1, 4, caughtUp: false);
      await second.settled();
      expect(second.api.requests, hasLength(1));
      expect(await second.held(), {
        1: [1, 2, 3, 4],
      });

      second.api.requests.first.response.complete();
      await pumpEventQueue();
      expect(second.api.sent, [
        [1, 2, 3],
        [4],
      ]);
      second.api.requests.last.response.complete();
      await Future.wait([flush, receipt]);
      expect(await second.held(), isNull);
    });

    test('a flush joined while one runs sends nothing twice', () async {
      await leaveUnconfirmedReads();
      final second = launch();
      final flushes = [
        second.controller.flush(_site),
        second.controller.flush(_site),
      ];
      await second.settled();
      second.answered!(_site);
      await second.settled();
      expect(second.api.requests, hasLength(1));
      second.api.requests.single.response.complete();
      await Future.wait(flushes);
      expect(second.api.requests, hasLength(1));
    });

    test('a restore that outlives its account restores nothing', () async {
      await leaveUnconfirmedReads();
      final second = launch();

      final flush = second.controller.flush(_site);
      second.lifecycle.invalidate(_site);
      await flush;
      await second.settled();

      expect(second.api.requests, isEmpty);
      expect(second.controller.lastReadPostNumberFor(_site, 1), isNull);
    });

    test('a read before the restore is not overwritten by it', () async {
      await leaveUnconfirmedReads();
      final second = launch();

      final receipt = second.controller.mark(_site, 2, 7, caughtUp: false);
      await second.settled();
      expect(await second.held(), {
        1: [1, 2, 3],
        2: [7],
      });
      second.api.requests.single.response.complete();
      await receipt;
    });

    test('a kill before the restore lands keeps the earlier session', () async {
      await leaveUnconfirmedReads();
      final second = launch();

      unawaited(second.controller.mark(_site, 2, 7, caughtUp: false));
      second.controller.dispose();

      expect((await second.held())?[1], [1, 2, 3]);
    });

    test('a reset drops the topic from the file', () async {
      await leaveUnconfirmedReads();
      final second = launch();
      await second.settled();
      second.controller.lastReadPostNumberFor(_site, 1);
      final restored = second.controller.flush(_site);
      await second.settled();
      second.api.requests.single.response.completeError(_offline);
      await restored;
      expect(await second.held(), {
        1: [1, 2, 3],
      });

      await second.controller.reset(
        _site,
        1,
        lease: second.lifecycle.capture(_site),
        write: () async {},
        accepted: () async {},
        onError: (error, _) => fail('$error'),
        onChanged: () {},
      );

      expect(await second.held(), isNull);
      await second.controller.flush(_site);
      expect(second.api.requests, hasLength(1));
    });
  });

  group('bounds', () {
    test('a topic keeps the highest posts one request carries', () {
      final bounded = boundTopicReads({
        1: [for (var post = 250; post >= 1; post--) post],
      });

      expect(bounded[1], [for (var post = 151; post <= 250; post++) post]);
    });

    test('a site keeps its most recently read topics', () {
      final bounded = boundTopicReads({
        for (var topic = 1; topic <= maximumPendingTopics + 5; topic++)
          topic: [1],
      });

      expect(bounded, hasLength(maximumPendingTopics));
      expect(bounded.keys.first, 6);
    });

    test('unusable entries in the file are ignored', () async {
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'sites': {
            _site: {
              'account': 'user:sam',
              'entries': {
                '1': [3, 'four', -1, 3, 2],
                'zero': [1],
                '-4': [1],
                '9': 'posts',
                '10': <int>[],
              },
            },
          },
        }),
      );

      expect(
        await createTopicReadOutbox(() => file).restore(_site, 'user:sam'),
        {
          1: [2, 3],
        },
      );
    });
  });
}
