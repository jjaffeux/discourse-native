import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  for (final trackerChange in [false, true]) {
    test(
      'lifecycle dispatch survives entry release (tracker=$trackerChange)',
      () async {
        final ports = EventTestPorts();
        addTearDown(ports.close);
        final firstEvent = PostEvent.decode(eventJson())!;
        final secondWire = eventJson(
          overrides: {
            'id': 43,
            'post': {
              'id': 43,
              'post_number': 1,
              'topic': {'id': 701},
            },
          },
        );
        ports.transport.responses['GET /discourse-post-event/events/42.json'] =
            {'event': eventJson()};
        ports.transport.responses['GET /discourse-post-event/events/43.json'] =
            {'event': secondWire};
        final first = ports.controller.acquire(eventSite, firstEvent);
        final second = ports.controller.acquire(
          eventSite,
          PostEvent.decode(secondWire)!,
        );
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        await pumpEventQueue();
        first.changes.addListener(() {
          if (first.loading) first.dispose();
        });
        final replacement = RecordingPluginLiveChannels();
        if (trackerChange) {
          expect(
            () => ports.controller.attachPluginTracker(eventSite, replacement),
            returnsNormally,
          );
        } else {
          ports.controller.setForeground(false);
          expect(() => ports.controller.setForeground(true), returnsNormally);
        }
        await pumpEventQueue();
        expect(first.isCurrent, isFalse);
        expect(second.isCurrent, isTrue);
        expect(
          ports.transport.requests.where(
            (r) => r.path == '/discourse-post-event/events/43.json',
          ),
          hasLength(2),
        );
        final channels = trackerChange ? replacement : ports.channels;
        expect(channels.subscriberCount('/discourse-post-event/700'), 0);
        expect(channels.subscriberCount('/discourse-post-event/701'), 1);
      },
    );
  }

  test(
    'a closed event controller rejects new handles without subscriptions',
    () {
      final ports = EventTestPorts();
      ports.controller.dispose();
      addTearDown(ports.environment.dispose);
      EventHandle? handle;
      try {
        expect(
          () => handle = ports.controller.acquire(
            eventSite,
            PostEvent.decode(eventJson())!,
          ),
          throwsStateError,
        );
        expect(ports.channels.channels, isEmpty);
        expect(ports.transport.requests, isEmpty);
      } finally {
        handle?.dispose();
        ports.channels.clear();
      }
    },
  );

  test(
    'retirement inside subscription admission cancels the returned resource',
    () {
      final ports = EventTestPorts();
      addTearDown(ports.close);
      final channels = _RetiringChannels();
      final controller = EventController(
        api: ports.controller.api,
        requests: ports.requests,
        posts: ports.posts,
        siteState: ports.controller.siteState,
        accounts: ports.controller.accounts,
        topics: ports.controller.topics,
        trackers: (_) => channels,
        zones: ports.zones,
      );
      channels.onSubscribe = controller.dispose;
      final handle = controller.acquire(
        eventSite,
        PostEvent.decode(eventJson())!,
      );
      addTearDown(handle.dispose);
      addTearDown(channels.channels.clear);
      expect(handle.isCurrent, isFalse);
      expect(channels.channels.channels, isEmpty);
      expect(ports.transport.requests, isEmpty);
    },
  );
}

final class _RetiringChannels implements PluginLiveChannelHandle {
  final channels = RecordingPluginLiveChannels();
  void Function()? onSubscribe;
  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    final subscription = channels.subscribe(channel, onMessage, lastId: lastId);
    onSubscribe?.call();
    return subscription;
  }
}
