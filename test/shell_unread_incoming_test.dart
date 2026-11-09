import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/models/discourse_model_codec.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

DiscourseUser _user({required bool unifiedNew}) =>
    const DiscourseModelCodec.core().currentUser({
      'id': 7,
      'username': 'reader',
      'unified_new_enabled': unifiedNew,
    }, _site);

final class _Bus implements SiteMessageBusSession {
  final Map<String, void Function(Object?, int)> _channels = {};

  void deliver(String channel, Object? data) => _channels[channel]!(data, 1);

  @override
  SiteMessageBusSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    _channels[channel] = onMessage;
    return _Subscription();
  }

  @override
  void start() {}

  @override
  void stop() {}

  @override
  void pollNow() {}

  @override
  Future<void> close() async {}
}

final class _Subscription implements SiteMessageBusSubscription {
  @override
  int? get lastId => null;

  @override
  void cancel() {}
}

Future<({SiteTracker tracker, _Bus bus})> _connected(DiscourseUser user) async {
  SharedPreferences.setMockInitialValues({});
  final bus = _Bus();
  late SiteTracker built;
  final config = SiteConfig.fromSettings(const {});
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user, config: config),
    ]),
    api: FakeDiscourseApi(user: user, siteConfigs: {_site: config}),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers:
        ({
          required siteUrl,
          required onIncomingTopics,
          required onNotifications,
          required onReviewableCounts,
          admitIncoming,
          userId,
          apiKey,
          clientId,
          shouldLongPoll,
          initialLastIds = const {},
        }) => built = SiteTracker(
          siteUrl: siteUrl,
          onIncomingTopics: onIncomingTopics,
          onNotifications: onNotifications,
          onReviewableCounts: onReviewableCounts,
          admitIncoming: admitIncoming,
          userId: userId,
          apiKey: apiKey,
          clientId: clientId,
          initialLastIds: initialLastIds,
          httpClient: MockClient((_) async => http.Response('', 200)),
          messageBus: bus,
        ),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  return (tracker: built, bus: bus);
}

Map<String, Object?> _unread(int id) => {
  'topic_id': id,
  'message_type': 'unread',
  'payload': {'highest_post_number': 4, 'category_id': 5},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a unified New list announces a reply to a read topic', () async {
    final (:tracker, :bus) = await _connected(_user(unifiedNew: true));

    bus.deliver('/unread', _unread(30));

    expect(tracker.incoming.topicIds('new'), [30]);
  });

  test('a classic New list does not announce a reply', () async {
    final (:tracker, :bus) = await _connected(_user(unifiedNew: false));

    bus.deliver('/unread', _unread(30));

    expect(tracker.incoming.count('new'), 0);
    expect(tracker.incoming.topicIds('unread'), [30]);
  });

  test('a list of new topics only never announces a reply', () async {
    final (:tracker, :bus) = await _connected(_user(unifiedNew: true));

    bus.deliver('/unread', _unread(30));

    expect(tracker.incoming.count('new-topics'), 0);
  });
}
