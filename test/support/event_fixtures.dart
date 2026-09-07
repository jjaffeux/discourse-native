import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_api.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_controller.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';

const eventSite = 'https://forum.example';
Map<String, dynamic> eventJson({Map<String, Object?> overrides = const {}}) => {
  'id': 42,
  'name': 'Engineering Managers Call',
  'starts_at': '2026-09-08T23:00:00+02:00',
  'ends_at': '2026-09-09T00:00:00+02:00',
  'timezone': 'Europe/Paris',
  'recurrence': 'every_week',
  'status': 'private',
  'is_private': true,
  'is_public': false,
  'is_standalone': false,
  'is_closed': false,
  'is_expired': false,
  'can_update_attendance': true,
  'can_act_on_discourse_post_event': true,
  'should_display_invitees': true,
  'creator': {'id': 1, 'username': 'sam', 'name': 'Sam'},
  'sample_invitees': [
    {
      'user': {'id': 2, 'username': 'lee'},
      'status': null,
      'recurring': false,
    },
  ],
  'stats': {
    'going': 9,
    'going_recurring': 7,
    'interested': 2,
    'not_going': 1,
    'invited': 15,
  },
  'watching_invitee': null,
  'url': 'https://meet.example/team',
  'post': {
    'id': 42,
    'post_number': 1,
    'url': '/t/managers/700/1',
    'topic': {'id': 700, 'title': 'Managers'},
  },
  ...overrides,
};

Map<String, Object?> watching({
  String status = 'going',
  bool recurring = false,
}) => {
  'id': 83,
  'status': status,
  'recurring': recurring,
  'user': {'id': 2, 'username': 'lee'},
};

final class EventTestPorts {
  EventTestPorts({RecordingPluginTransport? transport})
    : transport = transport ?? RecordingPluginTransport() {
    environment.setDeviceTimezone('Etc/UTC');
    zones = PluginTimezoneHost(
      readerTimezone: environment.readerTimezone,
      location: environment.location,
      timezoneNames: () => environment.timezoneNames,
      changes: environment,
    );
    controller = EventController(
      api: EventApi(this.transport),
      requests: requests,
      posts: posts,
      siteState: PluginSiteStateHost(
        currentUserFor: (_) => user,
        siteConfigFor: (_) => SiteConfig(
          plugins: PluginData.none.withValue(
            eventSettingsKey,
            const EventSettings(enabled: true),
          ),
        ),
      ),
      accounts: EventTestConnection(),
      topics: PluginTopicRefreshHost(
        reloadTopic: (site, topic) async {
          refreshedTopics.add((site, topic));
        },
      ),
      trackers: (_) => channels,
      zones: zones,
    );
  }
  final RecordingPluginTransport transport;
  DiscourseUser? user = const DiscourseUser(
    username: 'lee',
    id: 2,
    timezone: 'Europe/Paris',
  );
  final requests = PluginTestRequestHost(
    apiKeys: {eventSite: 'key', 'https://other.example': 'other-key'},
  );
  final posts = EventTestPosts();
  final channels = RecordingPluginLiveChannels();
  final environment = TimezoneEnvironment.forTesting(
    detectDeviceTimezone: () async => 'Etc/UTC',
  );
  late final PluginTimezoneHost zones;
  late final EventController controller;
  final refreshedTopics = <(String, int)>[];
  void close() {
    controller.dispose();
    environment.dispose();
  }
}

final class EventTestConnection implements PluginAccountConnectionHost {
  @override
  bool isConnected(String siteUrl) => true;
  @override
  Future<String?> connect(String siteUrl) async => 'key';
}

final class EventTestPosts implements PluginPostHost {
  final lanes = <(String, int)>{};
  bool archived = false;
  void Function()? onBeginWrite;
  @override
  Post? readPost(String siteUrl, int postId) => null;
  @override
  bool topicArchived(String siteUrl, int topicId) => archived;
  @override
  bool beginWrite(String siteUrl, int postId) {
    final added = lanes.add((siteUrl, postId));
    if (added) onBeginWrite?.call();
    return added;
  }

  @override
  void endWrite(String siteUrl, int postId) => lanes.remove((siteUrl, postId));
  @override
  bool writeInFlight(String siteUrl, int postId) =>
      lanes.contains((siteUrl, postId));
  @override
  void updatePluginRecord<T extends Object>(
    String siteUrl,
    int postId,
    PluginDataKey<T> key,
    T? Function(T?) update,
  ) {}
  @override
  Future<void> refreshPost({
    required String siteUrl,
    required int topicId,
    required int postId,
    required String? apiKey,
    required PluginSiteLease lease,
  }) async {}
}
