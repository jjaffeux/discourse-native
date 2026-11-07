import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
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
