import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:message_bus_client/message_bus_client.dart';

void main() {
  test('rejects remote HTTP before starting a poll', () {
    var requestCount = 0;

    expect(
      () => SiteTracker(
        siteUrl: 'http://example.com',
        onIncomingTopics: () {},
        onNotifications: (_) {},
        onReviewableCounts: (_) {},
        httpClient: MockClient((_) async {
          requestCount += 1;
          return http.Response('', 200);
        }),
      ),
      throwsA(isA<SiteLookupException>()),
    );
    expect(requestCount, 0);
  });

  test('polls never follow redirects carrying an API key', () async {
    final firstRequest = Completer<http.Request>();
    final tracker = SiteTracker(
      siteUrl: 'https://example.com',
      apiKey: 'secret',
      clientId: 'client-id',
      onIncomingTopics: () {},
      onNotifications: (_) {},
      onReviewableCounts: (_) {},
      shouldLongPoll: () => false,
      httpClient: MockClient((request) async {
        if (!firstRequest.isCompleted) firstRequest.complete(request);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://attacker.example/message-bus/poll'},
        );
      }),
    );
    addTearDown(tracker.dispose);

    final request = await firstRequest.future.timeout(
      const Duration(seconds: 1),
    );
    expect(request.followRedirects, isFalse);
    expect(request.headers['User-Api-Key'], 'secret');
    expect(request.headers['User-Api-Client-Id'], 'client-id');
    expect(request.bodyFields['/latest'], '-1');
    expect(request.bodyFields['/new'], '-1');
  });

  test('registers account channels and forwards message data', () async {
    final bus = _FakeMessageBusSession();
    var incomingCalls = 0;
    final notifications = <Object?>[];
    final reviewableCounts = <Object?>[];
    final tracker = SiteTracker(
      siteUrl: 'https://meta.discourse.org',
      userId: 42,
      apiKey: 'secret',
      clientId: 'client-id',
      onIncomingTopics: () => incomingCalls += 1,
      onNotifications: notifications.add,
      onReviewableCounts: reviewableCounts.add,
      httpClient: MockClient((_) async => http.Response('', 200)),
      messageBus: bus,
    );
    addTearDown(tracker.dispose);

    expect(bus.channels, {
      '/latest',
      '/new',
      '/notification/42',
      '/reviewable_counts/42',
    });

    bus.deliver('/latest', {'topic_id': 7, 'message_type': 'new_topic'});
    bus.deliver('/latest', {'topic_id': 7, 'message_type': 'new_topic'});
    bus.deliver('/notification/42', {'id': 1});
    bus.deliver('/reviewable_counts/42', {'pending_count': 3});

    expect(incomingCalls, 1);
    expect(tracker.incoming.topicIds('latest'), [7]);
    expect(notifications, [
      {'id': 1},
    ]);
    expect(reviewableCounts, [
      {'pending_count': 3},
    ]);
  });

  test('signed-out trackers only subscribe to public topics', () async {
    final bus = _FakeMessageBusSession();
    final tracker = _tracker(bus, userId: 42);
    addTearDown(tracker.dispose);

    expect(bus.channels, {'/latest'});
  });

  test('callback diagnostics never retain a message-bus payload', () async {
    const secretPayload = '{"api_key":"message-bus-payload-secret"}';
    final diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'message-bus-privacy',
    );
    final binding = DiagnosticsSink.install(diagnostics);
    addTearDown(() async {
      binding.close();
      await diagnostics.close();
    });
    final bus = _FakeMessageBusSession();
    final tracker = _tracker(bus);
    addTearDown(tracker.dispose);

    bus.emitError(
      MessageBusCallbackException(
        '/latest',
        const FormatException('invalid callback payload', secretPayload, 1),
        StackTrace.current,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final event = diagnostics.events.whereType<ErrorDiagnosticEvent>().single;
    expect(event.operation, 'messageBus.callback /latest');
    expect(event.message, contains('invalid callback payload'));
    expect(event.toString(), isNot(contains(secretPayload)));
    expect(diagnostics.buildJsonReport(), isNot(contains(secretPayload)));
    expect(
      diagnostics.buildJsonReport(),
      isNot(contains('message-bus-payload-secret')),
    );
  });

  test('start stop and pollNow avoid redundant bus work', () async {
    final bus = _FakeMessageBusSession();
    final tracker = _tracker(bus);
    addTearDown(tracker.dispose);

    tracker.start();
    tracker.pollNow();
    tracker.stop();
    tracker.stop();
    tracker.pollNow();
    tracker.start();
    tracker.start();
    tracker.pollNow();

    expect(bus.startCalls, 2);
    expect(bus.stopCalls, 1);
    expect(bus.pollNowCalls, 2);
  });

  test('a failed restart remains retryable', () async {
    final bus = _FakeMessageBusSession();
    final tracker = _tracker(bus);
    addTearDown(tracker.dispose);
    tracker.stop();
    bus.failNextStart = true;

    expect(tracker.start, throwsStateError);
    tracker.start();
    tracker.pollNow();

    expect(bus.startCalls, 3);
    expect(bus.pollNowCalls, 1);
  });

  test('a failed stop retains polling state until a retry succeeds', () async {
    final bus = _FakeMessageBusSession()..failNextStop = true;
    final tracker = _tracker(bus);
    addTearDown(tracker.dispose);

    expect(tracker.stop, throwsStateError);
    tracker.pollNow();
    tracker.stop();
    tracker.pollNow();

    expect(bus.stopCalls, 2);
    expect(bus.pollNowCalls, 1);
  });

  test(
    'watchTopic deduplicates channels and suppresses unwatched callbacks',
    () async {
      final bus = _FakeMessageBusSession();
      final tracker = _tracker(bus);
      addTearDown(tracker.dispose);
      final messages = <(String, Object?)>[];

      tracker.watchTopic(12, [
        '/topic/12',
        '/topic/12',
        '/topic/12/status',
      ], (channel, data) => messages.add((channel, data)));
      final topicCallback = bus.retainedCallback('/topic/12');

      expect(tracker.watchedTopic, 12);
      expect(bus.activeSubscriptionCount('/topic/12'), 1);
      expect(bus.activeSubscriptionCount('/topic/12/status'), 1);

      bus.deliver('/topic/12', 'first');
      tracker.unwatchTopic();
      topicCallback('late');

      expect(messages, [('/topic/12', 'first')]);
      expect(tracker.watchedTopic, isNull);
      expect(bus.activeSubscriptionCount('/topic/12'), 0);
      expect(bus.activeSubscriptionCount('/topic/12/status'), 0);
    },
  );

  test(
    'switching topics suppresses a callback retained by the old watch',
    () async {
      final bus = _FakeMessageBusSession();
      final tracker = _tracker(bus);
      addTearDown(tracker.dispose);
      final messages = <(String, Object?)>[];

      tracker.watchTopic(12, [
        '/topic/12',
      ], (channel, data) => messages.add((channel, data)));
      final oldCallback = bus.retainedCallback('/topic/12');
      tracker.watchTopic(13, [
        '/topic/13',
      ], (channel, data) => messages.add((channel, data)));

      oldCallback('late');
      bus.deliver('/topic/13', 'current');

      expect(messages, [('/topic/13', 'current')]);
      expect(tracker.watchedTopic, 13);
    },
  );

  test('a failed topic watch rolls back partial subscriptions', () async {
    final bus = _FakeMessageBusSession()..failingChannel = '/topic/12/status';
    final tracker = _tracker(bus);
    addTearDown(tracker.dispose);

    expect(
      () =>
          tracker.watchTopic(12, ['/topic/12', '/topic/12/status'], (_, _) {}),
      throwsStateError,
    );

    expect(tracker.watchedTopic, isNull);
    expect(bus.activeSubscriptionCount('/topic/12'), 0);
  });

  test(
    'plugin watches forward snapshot cursors and can be cancelled',
    () async {
      final bus = _FakeMessageBusSession();
      final tracker = _tracker(bus);
      addTearDown(tracker.dispose);
      final messages = <Object?>[];

      final subscription = tracker.watchPluginChannel(
        '/resenha/rooms/index',
        messages.add,
        lastId: 144,
      );
      expect(bus.lastIds['/resenha/rooms/index'], 144);

      bus.deliver('/resenha/rooms/index', 'first');
      subscription.cancel();
      bus.deliver('/resenha/rooms/index', 'late');

      expect(messages, ['first']);
      expect(bus.activeSubscriptionCount('/resenha/rooms/index'), 0);
    },
  );

  test(
    'reports a failed topic unsubscribe while the tracker is active',
    () async {
      final diagnostics = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'message-bus-unsubscribe',
      );
      final binding = DiagnosticsSink.install(diagnostics);
      addTearDown(() async {
        binding.close();
        await diagnostics.close();
      });
      final bus = _FakeMessageBusSession()
        ..failingCancellationChannel = '/topic/12';
      final tracker = _tracker(bus);
      addTearDown(tracker.dispose);
      tracker.watchTopic(12, ['/topic/12'], (_, _) {});

      tracker.unwatchTopic();

      final event = diagnostics.events.whereType<ErrorDiagnosticEvent>().single;
      expect(event.operation, 'messageBus.unsubscribeTopic');
      expect(event.source, 'message_bus');
      expect(event.errorType, 'StateError');
      expect(event.message, contains('subscription cancellation failed'));
      expect(event.severity, DiagnosticSeverity.warning);
      expect(event.handled, isTrue);
      expect(event.degraded, isTrue);
    },
  );

  test('a constructor subscription failure closes its partial session', () {
    final bus = _FakeMessageBusSession()..failingChannel = '/new';
    var incomingCalls = 0;

    expect(
      () => _tracker(
        bus,
        apiKey: 'secret',
        onIncomingTopics: () => incomingCalls += 1,
      ),
      throwsStateError,
    );

    expect(bus.startCalls, 0);
    expect(bus.closeCalls, 1);
    bus.retainedCallback('/latest')({
      'topic_id': 7,
      'message_type': 'new_topic',
    });
    expect(incomingCalls, 0);
  });

  test(
    'dispose is idempotent and suppresses every retained callback',
    () async {
      final bus = _FakeMessageBusSession();
      var incomingCalls = 0;
      var notificationCalls = 0;
      var reviewableCalls = 0;
      var topicCalls = 0;
      final tracker = _tracker(
        bus,
        userId: 42,
        apiKey: 'secret',
        onIncomingTopics: () => incomingCalls += 1,
        onNotifications: (_) => notificationCalls += 1,
        onReviewableCounts: (_) => reviewableCalls += 1,
      );
      tracker.watchTopic(12, ['/topic/12'], (_, _) => topicCalls += 1);
      final incomingCallback = bus.retainedCallback('/latest');
      final notificationCallback = bus.retainedCallback('/notification/42');
      final reviewableCallback = bus.retainedCallback('/reviewable_counts/42');
      final topicCallback = bus.retainedCallback('/topic/12');
      tracker.incoming.notify({'topic_id': 7, 'message_type': 'new_topic'});
      expect(tracker.incoming.count('latest'), 1);

      final firstDispose = tracker.dispose();
      final secondDispose = tracker.dispose();
      incomingCallback({'topic_id': 1, 'message_type': 'new_topic'});
      notificationCallback({});
      reviewableCallback({});
      topicCallback({});
      tracker.stop();
      tracker.pollNow();

      expect(identical(firstDispose, secondDispose), isTrue);
      await firstDispose;
      expect(bus.closeCalls, 1);
      expect(tracker.watchedTopic, isNull);
      expect(tracker.incoming.count('latest'), 0);
      expect(incomingCalls, 0);
      expect(notificationCalls, 0);
      expect(reviewableCalls, 0);
      expect(topicCalls, 0);
      expect(() => tracker.start(), throwsStateError);
      expect(
        () => tracker.watchTopic(13, ['/topic/13'], (_, _) {}),
        throwsStateError,
      );
    },
  );

  test('a broken topic cancellation cannot prevent session close', () async {
    final bus = _FakeMessageBusSession()
      ..failingCancellationChannel = '/topic/12';
    final tracker = _tracker(bus);
    tracker.watchTopic(12, ['/topic/12', '/topic/12/status'], (_, _) {});

    await tracker.dispose();

    expect(tracker.watchedTopic, isNull);
    expect(bus.closeCalls, 1);
    expect(bus.activeSubscriptionCount('/topic/12'), 0);
    expect(bus.activeSubscriptionCount('/topic/12/status'), 0);
  });
}

SiteTracker _tracker(
  _FakeMessageBusSession bus, {
  int? userId,
  String? apiKey,
  void Function()? onIncomingTopics,
  void Function(Object? data)? onNotifications,
  void Function(Object? data)? onReviewableCounts,
}) => SiteTracker(
  siteUrl: 'https://example.com',
  userId: userId,
  apiKey: apiKey,
  onIncomingTopics: onIncomingTopics ?? () {},
  onNotifications: onNotifications ?? (_) {},
  onReviewableCounts: onReviewableCounts ?? (_) {},
  httpClient: MockClient((_) async => http.Response('', 200)),
  messageBus: bus,
);

final class _FakeMessageBusSession
    implements SiteMessageBusSession, SiteMessageBusErrorSource {
  final Map<String, List<_FakeMessageBusSubscription>> _subscriptions = {};
  final Map<String, List<void Function(Object?)>> _retainedCallbacks = {};
  final Map<String, int?> lastIds = {};
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  String? failingChannel;
  String? failingCancellationChannel;
  bool failNextStart = false;
  bool failNextStop = false;
  int startCalls = 0;
  int stopCalls = 0;
  int pollNowCalls = 0;
  int closeCalls = 0;

  Set<String> get channels => _subscriptions.keys.toSet();

  @override
  Stream<Object> get errors => _errors.stream;

  void emitError(Object error) => _errors.add(error);

  int activeSubscriptionCount(String channel) =>
      _subscriptions[channel]
          ?.where((subscription) => !subscription.cancelled)
          .length ??
      0;

  void deliver(String channel, Object? data) {
    final subscriptions = List.of(
      _subscriptions[channel] ?? const <_FakeMessageBusSubscription>[],
    );
    for (final subscription in subscriptions) {
      if (!subscription.cancelled) subscription.callback(data);
    }
  }

  void Function(Object?) retainedCallback(String channel) =>
      _retainedCallbacks[channel]!.last;

  @override
  SiteMessageBusSubscription subscribe(
    String channel,
    void Function(Object? data) onMessage, {
    int? lastId,
  }) {
    if (channel == failingChannel) {
      throw StateError('subscription failed');
    }
    final subscription = _FakeMessageBusSubscription(
      onMessage,
      throwsOnCancel: channel == failingCancellationChannel,
    );
    (_subscriptions[channel] ??= []).add(subscription);
    lastIds[channel] = lastId;
    (_retainedCallbacks[channel] ??= []).add(onMessage);
    return subscription;
  }

  @override
  void start() {
    startCalls += 1;
    if (!failNextStart) return;
    failNextStart = false;
    throw StateError('start failed');
  }

  @override
  void stop() {
    stopCalls += 1;
    if (!failNextStop) return;
    failNextStop = false;
    throw StateError('stop failed');
  }

  @override
  void pollNow() => pollNowCalls += 1;

  @override
  Future<void> close() async {
    closeCalls += 1;
    await _errors.close();
  }
}

final class _FakeMessageBusSubscription implements SiteMessageBusSubscription {
  _FakeMessageBusSubscription(this.callback, {this.throwsOnCancel = false});

  final void Function(Object?) callback;
  final bool throwsOnCancel;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
    if (throwsOnCancel) throw StateError('subscription cancellation failed');
  }
}
