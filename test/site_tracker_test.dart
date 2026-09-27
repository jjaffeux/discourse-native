import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:message_bus_client/message_bus_client.dart';

import 'support/bundled_plugins.dart';

void main() {
  group('SiteTracker', () {
    group('connection and core-channel setup', () {
      test('rejects remote HTTP before polling', () {
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

      test('disables redirects on polls carrying an API key', () async {
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
        tracker.start();

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
          initialLastIds: const {
            '/latest': 101,
            '/new': 102,
            '/notification/42': 103,
            '/reviewable_counts/42': 104,
          },
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
        expect(bus.lastIds, {
          '/latest': 101,
          '/new': 102,
          '/notification/42': 103,
          '/reviewable_counts/42': 104,
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

      test('mirrors topic-tracking channels through one callback', () async {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus, userId: 42, apiKey: 'secret');
        addTearDown(tracker.dispose);
        final messages = <Object?>[];

        tracker.watchTopicTrackingState(
          42,
          messages.add,
          lastIds: const {
            '/unread': 201,
            '/unread/42': 202,
            '/delete': 203,
            '/recover': 204,
            '/destroy': 205,
          },
        );

        expect(bus.channels, {
          '/latest',
          '/new',
          '/unread',
          '/unread/42',
          '/delete',
          '/recover',
          '/destroy',
          '/notification/42',
          '/reviewable_counts/42',
        });
        expect(bus.lastIds, containsPair('/unread', 201));
        expect(bus.lastIds, containsPair('/unread/42', 202));
        expect(bus.lastIds, containsPair('/delete', 203));
        expect(bus.lastIds, containsPair('/recover', 204));
        expect(bus.lastIds, containsPair('/destroy', 205));

        const latest = {'topic_id': 7, 'message_type': 'new_topic'};
        const unread = {'topic_id': 8, 'message_type': 'unread'};
        bus.deliver('/latest', latest);
        bus.deliver('/unread/42', unread);

        expect(messages, [latest, unread]);
      });

      test('ignores invalid refresh IDs and keeps delivering updates', () {
        final bus = _FakeMessageBusSession();
        var incomingCalls = 0;
        final tracker = _tracker(
          bus,
          userId: 42,
          apiKey: 'secret',
          onIncomingTopics: () => incomingCalls++,
        );
        addTearDown(tracker.dispose);
        final trackingMessages = <Object?>[];
        tracker.watchTopicTrackingState(42, trackingMessages.add);
        final refreshes = <Set<int>>[];
        tracker.watchTopic(7, pluginRegistry.topicChannels(7), (channel, data) {
          final ids = pluginRegistry.stalePosts(channel, data);
          if (ids.isNotEmpty) refreshes.add(ids);
        });

        for (final channel in ['/latest', '/new']) {
          bus.deliver(
            channel,
            jsonDecode('{"topic_id":1e999,"message_type":"new_topic"}'),
          );
          bus.deliver(channel, const {
            'topic_id': 3.75,
            'message_type': 'latest',
          });
        }
        for (final channel in ['/polls/7', '/topic/7/reactions']) {
          bus.deliver(channel, jsonDecode('{"post_id":1e999}'));
          bus.deliver(channel, const {'post_id': 9.75});
          bus.deliver(channel, const {'post_id': double.nan});
        }
        expect(incomingCalls, 0);
        expect(tracker.incoming.topicIds('latest'), isEmpty);
        expect(tracker.incoming.topicIds('new'), isEmpty);
        expect(trackingMessages, hasLength(4));
        expect(refreshes, isEmpty);

        bus.deliver('/latest', const {
          'topic_id': 7,
          'message_type': 'new_topic',
        });
        bus.deliver('/new', const {
          'topic_id': 7.0,
          'message_type': 'new_topic',
        });
        bus.deliver('/latest', const {'topic_id': 8, 'message_type': 'latest'});
        bus.deliver('/polls/7', const {'post_id': 9.0});
        bus.deliver('/topic/7/reactions', const {'post_id': 10});

        expect(incomingCalls, 2);
        expect(tracker.incoming.topicIds('latest'), [7, 8]);
        expect(tracker.incoming.topicIds('new'), [7]);
        expect(trackingMessages, hasLength(7));
        expect(refreshes, [
          {9},
          {10},
        ]);
      });

      test('limits signed-out subscriptions to public topics', () async {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus, userId: 42);
        addTearDown(tracker.dispose);

        expect(bus.channels, {'/latest'});
      });

      test('redacts message-bus payloads from callback diagnostics', () async {
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

        final event = diagnostics.events
            .whereType<ErrorDiagnosticEvent>()
            .single;
        expect(event.operation, 'messageBus.callback /latest');
        expect(event.message, contains('invalid callback payload'));
        expect(event.toString(), isNot(contains(secretPayload)));
        expect(diagnostics.buildJsonReport(), isNot(contains(secretPayload)));
        expect(
          diagnostics.buildJsonReport(),
          isNot(contains('message-bus-payload-secret')),
        );
      });
    });

    group('polling lifecycle', () {
      test(
        'sends its first poll on start, carrying every registered channel',
        () async {
          // A channel added after a poll is sent makes that poll stale: the
          // client aborts it, after waiting up to firstChunkTimeout for a
          // pending `/__status` baseline, and polls again.
          final polls = <Map<String, String>>[];
          final held = Completer<http.Response>();
          addTearDown(() {
            if (!held.isCompleted) held.complete(http.Response('[]', 200));
          });
          final tracker = SiteTracker(
            siteUrl: 'https://example.com',
            userId: 42,
            apiKey: 'secret',
            clientId: 'client-id',
            onIncomingTopics: () {},
            onNotifications: (_) {},
            onReviewableCounts: (_) {},
            httpClient: MockClient((request) {
              polls.add(request.bodyFields);
              return held.future;
            }),
          );
          addTearDown(tracker.dispose);

          tracker.watchTopicTrackingState(42, (_) {});
          tracker.watchPluginChannel('/user-status', (_) {});
          await pumpEventQueue();

          expect(polls, isEmpty);

          tracker.start();
          await pumpEventQueue();

          expect(polls, hasLength(1));
          expect(
            polls.single.keys,
            containsAll([
              '/latest',
              '/new',
              '/notification/42',
              '/reviewable_counts/42',
              '/unread',
              '/unread/42',
              '/delete',
              '/recover',
              '/destroy',
              '/user-status',
            ]),
          );
        },
      );

      test(
        'avoids redundant bus work across start, stop, and pollNow',
        () async {
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
        },
      );

      test('remains retryable after a failed restart', () async {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);
        tracker.start();
        tracker.stop();
        bus.failNextStart = true;

        expect(tracker.start, throwsStateError);
        tracker.start();
        tracker.pollNow();

        expect(bus.startCalls, 3);
        expect(bus.pollNowCalls, 1);
      });

      test(
        'retains polling state until a failed stop retry succeeds',
        () async {
          final bus = _FakeMessageBusSession()..failNextStop = true;
          final tracker = _tracker(bus);
          addTearDown(tracker.dispose);
          tracker.start();

          expect(tracker.stop, throwsStateError);
          tracker.pollNow();
          tracker.stop();
          tracker.pollNow();

          expect(bus.stopCalls, 2);
          expect(bus.pollNowCalls, 1);
        },
      );
    });

    group('topic watches', () {
      test(
        'adds and removes another visible topic without changing the first',
        () {
          final bus = _FakeMessageBusSession();
          final tracker = _tracker(bus);
          addTearDown(tracker.dispose);
          final messages = <String>[];
          tracker.watchTopic(12, [
            '/topic/12',
          ], (channel, _) => messages.add('first $channel'));
          final firstTopicCallback = bus.retainedCallback('/topic/12');
          tracker.watchTopic(12, [
            '/topic/12',
            '/topic/13',
          ], (channel, _) => messages.add('both $channel'));
          expect(bus.activeSubscriptionCount('/topic/12'), 1);
          expect(bus.activeSubscriptionCount('/topic/13'), 1);
          final oldCallback = bus.retainedCallback('/topic/13');
          bus.deliver('/topic/13', 'visible');
          tracker.watchTopic(12, [
            '/topic/12',
          ], (channel, _) => messages.add('last $channel'));
          oldCallback('closed');
          firstTopicCallback('still live');

          expect(bus.subscribeCount('/topic/12'), 1);
          expect(bus.activeSubscriptionCount('/topic/12'), 1);
          expect(bus.activeSubscriptionCount('/topic/13'), 0);
          // A kept channel dispatches through the latest watch's callback.
          expect(messages, ['both /topic/13', 'last /topic/12']);
        },
      );

      test(
        'resumes a re-watched topic channel after its last delivery',
        () async {
          final bus = _FakeMessageBusSession();
          final tracker = _tracker(bus);
          addTearDown(tracker.dispose);
          const channels = ['/topic/7', '/polls/7'];

          tracker.watchTopic(
            7,
            channels,
            (_, _) {},
            lastIds: const {'/topic/7': 100},
          );
          bus.deliver('/polls/7', 'vote', messageId: 55);
          tracker.unwatchTopic();
          tracker.watchTopic(
            7,
            channels,
            (_, _) {},
            lastIds: const {'/topic/7': 100},
          );

          expect(bus.lastIds['/topic/7'], 100);
          expect(bus.lastIds['/polls/7'], 55);
        },
      );

      test('resumes a re-watched channel from its status baseline when nothing '
          'was delivered', () async {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);

        tracker.watchTopic(7, ['/topic/7', '/polls/7'], (_, _) {});
        bus.establishBaseline('/polls/7', 40);
        tracker.unwatchTopic();
        tracker.watchTopic(7, ['/topic/7', '/polls/7'], (_, _) {});

        expect(bus.lastIds['/polls/7'], 40);
        expect(bus.lastIds['/topic/7'], isNull);
      });

      test('resumes a core topic channel from the newer of its snapshot and '
          'read position', () async {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);

        tracker.watchTopic(
          7,
          ['/topic/7'],
          (_, _) {},
          lastIds: const {'/topic/7': 100},
        );
        bus.deliver('/topic/7', 'edit', messageId: 120);
        tracker.unwatchTopic();
        tracker.watchTopic(
          7,
          ['/topic/7'],
          (_, _) {},
          lastIds: const {'/topic/7': 100},
        );
        expect(bus.lastIds['/topic/7'], 120);

        tracker.unwatchTopic();
        tracker.watchTopic(
          7,
          ['/topic/7'],
          (_, _) {},
          lastIds: const {'/topic/7': 150},
        );
        expect(bus.lastIds['/topic/7'], 150);
      });

      test(
        'keeps a visible topic subscribed while another is added and removed',
        () async {
          final bus = _FakeMessageBusSession();
          final tracker = _tracker(bus);
          addTearDown(tracker.dispose);
          const first = ['/topic/7', '/polls/7'];

          tracker.watchTopic(
            7,
            first,
            (_, _) {},
            lastIds: const {'/topic/7': 100},
          );
          tracker.watchTopic(
            7,
            [...first, '/topic/12', '/polls/12'],
            (_, _) {},
            lastIds: const {'/topic/7': 100, '/topic/12': 300},
          );
          bus.deliver('/polls/12', 'vote', messageId: 9);
          tracker.watchTopic(
            7,
            first,
            (_, _) {},
            lastIds: const {'/topic/7': 100},
          );
          tracker.watchTopic(
            7,
            [...first, '/topic/12', '/polls/12'],
            (_, _) {},
            lastIds: const {'/topic/7': 100, '/topic/12': 300},
          );

          expect(bus.subscribeCount('/topic/7'), 1);
          expect(bus.subscribeCount('/polls/7'), 1);
          expect(bus.subscribeCount('/topic/12'), 2);
          expect(bus.lastIds['/polls/12'], 9);
        },
      );

      test(
        'forgets read positions of the least recently left channels',
        () async {
          final bus = _FakeMessageBusSession();
          final tracker = _tracker(bus);
          addTearDown(tracker.dispose);
          const capacity = SiteTracker.retainedTopicPositionCapacity;

          for (var topicId = 1; topicId <= capacity + 1; topicId++) {
            tracker.watchTopic(topicId, ['/polls/$topicId'], (_, _) {});
            bus.deliver('/polls/$topicId', 'vote', messageId: topicId);
          }
          tracker.unwatchTopic();
          tracker.watchTopic(1, ['/polls/1'], (_, _) {});
          tracker.watchTopic(2, ['/polls/2'], (_, _) {});

          expect(bus.lastIds['/polls/1'], isNull);
          expect(bus.lastIds['/polls/2'], 2);
        },
      );

      test('a replacement tracker starts from no read positions', () async {
        final firstBus = _FakeMessageBusSession();
        final first = _tracker(firstBus);
        first.watchTopic(7, ['/polls/7'], (_, _) {});
        firstBus.deliver('/polls/7', 'vote', messageId: 55);
        first.unwatchTopic();
        await first.dispose();

        // A new session: MessageBus positions never carry across sessions.
        final secondBus = _FakeMessageBusSession();
        final second = _tracker(secondBus, apiKey: 'secret');
        addTearDown(second.dispose);
        second.watchTopic(7, ['/polls/7'], (_, _) {});

        expect(secondBus.lastIds['/polls/7'], isNull);
      });

      test(
        'polls a re-watched channel from the head its first poll reported',
        () async {
          final polls = StreamController<Map<String, String>>.broadcast();
          addTearDown(polls.close);
          final tracker = SiteTracker(
            siteUrl: 'https://example.com',
            onIncomingTopics: () {},
            onNotifications: (_) {},
            onReviewableCounts: (_) {},
            httpClient: MockClient((request) async {
              final body = request.bodyFields;
              if (!polls.isClosed) polls.add(body);
              // A "new messages only" position is answered with the head.
              final messages = body['/polls/7'] != '-1'
                  ? const <Object?>[]
                  : <Object?>[
                      {
                        'global_id': -1,
                        'message_id': -1,
                        'channel': '/__status',
                        'data': {'/latest': 5, '/polls/7': 40},
                      },
                    ];
              return http.Response(
                jsonEncode(messages),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          );
          addTearDown(tracker.dispose);
          Future<Map<String, String>> nextPoll(
            bool Function(Map<String, String> body) matches,
          ) => polls.stream
              .firstWhere(matches)
              .timeout(const Duration(seconds: 2));
          const channels = ['/topic/7', '/polls/7'];
          const snapshot = {'/topic/7': 100};

          tracker.watchTopic(7, channels, (_, _) {}, lastIds: snapshot);
          final baseline = nextPoll((body) => body['/polls/7'] == '40');
          tracker.start();
          await baseline;
          final left = nextPoll((body) => !body.containsKey('/polls/7'));
          tracker.unwatchTopic();
          await left;
          final resumed = nextPoll((body) => body.containsKey('/polls/7'));
          tracker.watchTopic(7, channels, (_, _) {}, lastIds: snapshot);

          final body = await resumed;
          expect(body['/polls/7'], '40');
          expect(body['/topic/7'], '100');
        },
      );

      test('deduplicate channels and suppress unwatched callbacks', () async {
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
      });

      test('starts each topic channel from its server snapshot', () async {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);

        tracker.watchTopic(
          12,
          ['/topic/12', '/topic/12/status'],
          (_, _) {},
          lastIds: const {'/topic/12': 144},
        );

        expect(bus.lastIds['/topic/12'], 144);
        expect(bus.lastIds['/topic/12/status'], isNull);
      });

      test('suppress callbacks retained by a previous topic', () async {
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
      });

      test('roll back partial subscriptions after failure', () async {
        final bus = _FakeMessageBusSession()
          ..failingChannel = '/topic/12/status';
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);

        expect(
          () => tracker.watchTopic(12, [
            '/topic/12',
            '/topic/12/status',
          ], (_, _) {}),
          throwsStateError,
        );

        expect(tracker.watchedTopic, isNull);
        expect(bus.activeSubscriptionCount('/topic/12'), 0);
      });
    });

    group('plugin channels', () {
      test('forward snapshot cursors and can be cancelled', () async {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);
        final messages = <Object?>[];

        final subscription = tracker.watchPluginChannel(
          '/voice/rooms/index',
          messages.add,
          lastId: 144,
        );
        expect(bus.lastIds['/voice/rooms/index'], 144);

        final retainedCallback = bus.retainedCallback('/voice/rooms/index');
        bus.deliver('/voice/rooms/index', 'first');
        subscription.cancel();
        bus.deliver('/voice/rooms/index', 'late');
        retainedCallback('already queued');

        expect(messages, ['first']);
        expect(bus.activeSubscriptionCount('/voice/rooms/index'), 0);
      });

      test('scoped handles expose only declared live channels', () async {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);
        final messages = <(Object?, int)>[];
        final handle = tracker.pluginLiveChannels(const [
          PluginLiveChannelScope.prefix('/chat'),
        ]);

        expect(handle, isNot(isA<SiteTracker>()));
        final subscription = handle.subscribe(
          '/chat/42',
          (data, messageId) => messages.add((data, messageId)),
          lastId: 144,
        );
        final retainedCallback = bus.retainedCallback('/chat/42');
        bus.deliver('/chat/42', 'first', messageId: 145);
        subscription.cancel();
        bus.deliver('/chat/42', 'late', messageId: 146);
        retainedCallback('already queued');

        expect(bus.lastIds['/chat/42'], 144);
        expect(messages, [('first', 145)]);
        expect(bus.activeSubscriptionCount('/chat/42'), 0);
      });

      test('scoped handles expose no tracker control surface', () {
        final tracker = _tracker(_FakeMessageBusSession());
        addTearDown(tracker.dispose);
        final dynamic handle = tracker.pluginLiveChannels(const [
          PluginLiveChannelScope.prefix('/chat'),
        ]);

        for (final control in <void Function()>[
          // Deliberately probe the concrete wrapper as hostile dynamic code.
          // ignore: avoid_dynamic_calls
          () => handle.start(),
          // ignore: avoid_dynamic_calls
          () => handle.stop(),
          // ignore: avoid_dynamic_calls
          () => handle.pollNow(),
          // ignore: avoid_dynamic_calls
          () => handle.dispose(),
          // ignore: avoid_dynamic_calls
          () => handle.watchPluginChannel('/chat/42', (_) {}),
          // ignore: avoid_dynamic_calls
          () => handle.watchTopic(42, const ['/chat/42'], (_, _) {}),
        ]) {
          expect(control, throwsA(isA<NoSuchMethodError>()));
        }
      });

      test('scoped handles reject core, foreign, and spoofed channels', () {
        final bus = _FakeMessageBusSession();
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);
        final handle = tracker.pluginLiveChannels(const [
          PluginLiveChannelScope.prefix('/chat'),
          PluginLiveChannelScope.prefix('/latest'),
          PluginLiveChannelScope.prefix('/notification'),
          PluginLiveChannelScope.prefix('/topic'),
        ]);

        for (final channel in const [
          '/latest',
          '/latest/private',
          '/new',
          '/notification/42',
          '/reviewable_counts/42',
          '/user-status',
          '/do-not-disturb/42',
          '/topic/7/reactions',
          '/voice/rooms/7',
          '/chatty/42',
        ]) {
          expect(
            () => handle.subscribe(channel, (_, _) {}),
            throwsArgumentError,
            reason: channel,
          );
        }

        expect(bus.channels, {'/latest'});
      });
    });

    group('subscription and session cleanup', () {
      test('reports a failed topic unsubscribe while active', () async {
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

        final event = diagnostics.events
            .whereType<ErrorDiagnosticEvent>()
            .single;
        expect(event.operation, 'messageBus.unsubscribeTopic');
        expect(event.source, 'message_bus');
        expect(event.errorType, 'StateError');
        expect(event.message, contains('subscription cancellation failed'));
        expect(event.severity, DiagnosticSeverity.warning);
        expect(event.handled, isTrue);
        expect(event.degraded, isTrue);
      });

      test('constructor failure closes the partial session', () {
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
        'disposal is idempotent and suppresses retained callbacks',
        () async {
          final bus = _FakeMessageBusSession();
          var incomingCalls = 0;
          var notificationCalls = 0;
          var reviewableCalls = 0;
          var topicCalls = 0;
          var pluginCalls = 0;
          final tracker = _tracker(
            bus,
            userId: 42,
            apiKey: 'secret',
            onIncomingTopics: () => incomingCalls += 1,
            onNotifications: (_) => notificationCalls += 1,
            onReviewableCounts: (_) => reviewableCalls += 1,
          );
          addTearDown(tracker.dispose);
          tracker.watchTopic(12, ['/topic/12'], (_, _) => topicCalls += 1);
          tracker.watchPluginChannel(
            '/voice/rooms/index',
            (_) => pluginCalls += 1,
          );
          final incomingCallback = bus.retainedCallback('/latest');
          final notificationCallback = bus.retainedCallback('/notification/42');
          final reviewableCallback = bus.retainedCallback(
            '/reviewable_counts/42',
          );
          final topicCallback = bus.retainedCallback('/topic/12');
          final pluginCallback = bus.retainedCallback('/voice/rooms/index');
          tracker.incoming.notify({'topic_id': 7, 'message_type': 'new_topic'});
          expect(tracker.incoming.count('latest'), 1);

          final firstDispose = tracker.dispose();
          final secondDispose = tracker.dispose();
          incomingCallback({'topic_id': 1, 'message_type': 'new_topic'});
          notificationCallback({});
          reviewableCallback({});
          topicCallback({});
          pluginCallback({});
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
          expect(pluginCalls, 0);
          expect(() => tracker.start(), throwsStateError);
          expect(
            () => tracker.watchTopic(13, ['/topic/13'], (_, _) {}),
            throwsStateError,
          );
        },
      );

      test('broken topic cancellation cannot prevent session close', () async {
        final bus = _FakeMessageBusSession()
          ..failingCancellationChannel = '/topic/12';
        final tracker = _tracker(bus);
        addTearDown(tracker.dispose);
        tracker.watchTopic(12, ['/topic/12', '/topic/12/status'], (_, _) {});

        await tracker.dispose();

        expect(tracker.watchedTopic, isNull);
        expect(bus.closeCalls, 1);
        expect(bus.activeSubscriptionCount('/topic/12'), 0);
        expect(bus.activeSubscriptionCount('/topic/12/status'), 0);
      });

      test(
        'a tracking callback can dispose before incoming topics are published',
        () async {
          final bus = _FakeMessageBusSession();
          var incomingCalls = 0;
          final tracker = _tracker(
            bus,
            apiKey: 'secret',
            onIncomingTopics: () => incomingCalls++,
          );
          addTearDown(tracker.dispose);
          tracker.watchTopicTrackingState(42, (_) {
            unawaited(tracker.dispose());
          });

          bus.deliver('/latest', {'topic_id': 7, 'message_type': 'new_topic'});
          await tracker.dispose();

          expect(incomingCalls, 0);
          expect(tracker.incoming.count('latest'), 0);
        },
      );

      test(
        'topic cancellation can reenter disposal without closing twice',
        () async {
          final bus = _FakeMessageBusSession();
          final tracker = _tracker(bus);
          addTearDown(tracker.dispose);
          Future<void>? nested;
          bus.onSubscriptionCancel = () => nested = tracker.dispose();
          tracker.watchTopic(12, ['/topic/12'], (_, _) {});

          final closing = tracker.dispose();
          await closing;

          expect(nested, same(closing));
          expect(bus.closeCalls, 1);
        },
      );

      for (final synchronous in [false, true]) {
        test(
          'handles a ${synchronous ? 'synchronous' : 'future'} close failure while error cancellation is pending',
          () async {
            final failure = StateError('bus close failed');
            final cancelFailure = StateError(
              'error stream cancellation failed',
            );
            final uncaught = <Object>[];
            final delivered = Completer<Object>();
            late Completer<void> cancel;
            late StreamController<Object> errors;
            late _FakeMessageBusSession bus;
            runZonedGuarded(() {
              cancel = Completer<void>();
              errors = StreamController<Object>(onCancel: () => cancel.future);
              bus = _FakeMessageBusSession()
                ..errorStream = errors.stream
                ..onClose = () {
                  if (synchronous) throw failure;
                  return Future<void>.error(failure);
                };
              final tracker = _tracker(bus);
              unawaited(
                tracker.dispose().then<void>(
                  (_) => delivered.complete(StateError('unexpected success')),
                  onError: (Object error, StackTrace _) =>
                      delivered.complete(error),
                ),
              );
            }, (error, _) => uncaught.add(error));
            addTearDown(() async {
              if (!cancel.isCompleted) cancel.complete();
              await errors.close();
              await bus._errors.close();
            });

            // Let the close future fail before the separately controlled error
            // subscription finishes cancelling.
            await Future<void>.delayed(Duration.zero);
            cancel.completeError(cancelFailure);
            expect(await delivered.future, same(failure));
            await Future<void>.delayed(Duration.zero);

            expect(uncaught, isEmpty);
            expect(bus.closeCalls, 1);
          },
        );
      }
    });
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
  final Map<String, List<void Function(Object?, int)>> _retainedCallbacks = {};
  final Map<String, int?> lastIds = {};
  final Map<String, int> _subscribeCounts = {};
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  String? failingChannel;
  String? failingCancellationChannel;
  bool failNextStart = false;
  bool failNextStop = false;
  int startCalls = 0;
  int stopCalls = 0;
  int pollNowCalls = 0;
  int closeCalls = 0;
  Stream<Object>? errorStream;
  Future<void> Function()? onClose;
  void Function()? onSubscriptionCancel;

  Set<String> get channels => _subscriptions.keys.toSet();

  @override
  Stream<Object> get errors => errorStream ?? _errors.stream;

  void emitError(Object error) => _errors.add(error);

  int activeSubscriptionCount(String channel) =>
      _subscriptions[channel]
          ?.where((subscription) => !subscription.cancelled)
          .length ??
      0;

  int subscribeCount(String channel) => _subscribeCounts[channel] ?? 0;

  /// Like the client, a handle's position moves on receipt, before delivery.
  void deliver(String channel, Object? data, {int messageId = 1}) {
    final subscriptions = List.of(
      _subscriptions[channel] ?? const <_FakeMessageBusSubscription>[],
    );
    for (final subscription in subscriptions) {
      if (subscription.cancelled) continue;
      subscription.advance(messageId);
      subscription.callback(data, messageId);
    }
  }

  /// The `/__status` head a "new messages only" handle adopts on its first poll.
  void establishBaseline(String channel, int head) {
    for (final subscription
        in _subscriptions[channel] ?? const <_FakeMessageBusSubscription>[]) {
      if (!subscription.cancelled) subscription.position ??= head;
    }
  }

  void Function(Object?) retainedCallback(String channel) {
    final callback = _retainedCallbacks[channel]!.last;
    return (data) => callback(data, 1);
  }

  @override
  SiteMessageBusSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    if (channel == failingChannel) {
      throw StateError('subscription failed');
    }
    final subscription = _FakeMessageBusSubscription(
      onMessage,
      position: lastId,
      throwsOnCancel: channel == failingCancellationChannel,
      onCancel: onSubscriptionCancel,
    );
    (_subscriptions[channel] ??= []).add(subscription);
    _subscribeCounts[channel] = subscribeCount(channel) + 1;
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
  Future<void> close() {
    closeCalls += 1;
    return onClose?.call() ?? _errors.close();
  }
}

final class _FakeMessageBusSubscription implements SiteMessageBusSubscription {
  _FakeMessageBusSubscription(
    this.callback, {
    this.position,
    this.throwsOnCancel = false,
    this.onCancel,
  });

  final void Function(Object?, int) callback;
  final bool throwsOnCancel;
  final void Function()? onCancel;
  bool cancelled = false;
  int? position;

  /// As with the client's handle, a cancelled subscription has no position.
  @override
  int? get lastId => cancelled ? null : position;

  void advance(int messageId) {
    final current = position;
    if (current == null || messageId > current) position = messageId;
  }

  @override
  void cancel() {
    cancelled = true;
    onCancel?.call();
    if (throwsOnCancel) throw StateError('subscription cancellation failed');
  }
}
