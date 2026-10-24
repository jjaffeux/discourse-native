import 'dart:async';

import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://first.example';
const _reader = DiscourseUser(id: 7, username: 'reader');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ready connection survives background stop and foreground resume',
    () async {
      final shell = _shell(api: FakeDiscourseApi(user: _reader));
      addTearDown(shell.dispose);
      await shell.load();
      await pumpEventQueue();
      final tracker = FakeSiteTracker.built.single;
      expect(tracker.polling, isTrue);

      shell.setForeground(false);
      expect(tracker.polling, isFalse);
      expect(tracker.disposed, isFalse);
      shell.setForeground(true);
      await pumpEventQueue();

      expect(FakeSiteTracker.built, [tracker]);
      expect(tracker.polling, isTrue);
      expect(tracker.pollNowCalls, greaterThan(0));
    },
  );

  test(
    'same-lease account replacement reconnects private tracking authority',
    () async {
      final api = _ReplacementUserApi();
      final shell = _shell(api: api);
      addTearDown(shell.dispose);
      addTearDown(() {
        if (!api.response.isCompleted) api.response.complete(_reader);
      });
      await shell.load();
      await api.started.future;
      await pumpEventQueue();
      final original = FakeSiteTracker.built.single;
      final lease = shell.lifecycle.capture(_site);
      const next = DiscourseUser(id: 8, username: 'next-reader');

      api.response.complete(next);
      await pumpEventQueue();

      expect(lease.isCurrent, isTrue);
      expect(shell.currentInstance?.user?.id, 8);
      expect(original.disposed, isTrue);
      final replacement = FakeSiteTracker.built.last;
      expect(replacement.userId, 8);
      expect(replacement.disposed, isFalse);
      expect(replacement.polling, isTrue);
      final revision = shell.topicTrackingRevisionFor(_site);
      original.deliverTopicTracking(const {
        'message_type': 'new_topic',
        'topic_id': 20,
        'payload': {'highest_post_number': 1, 'created_in_new_period': true},
      });
      expect(shell.topicTrackingRevisionFor(_site), revision);
      replacement.deliverTopicTracking(const {
        'message_type': 'new_topic',
        'topic_id': 21,
        'payload': {'highest_post_number': 1, 'created_in_new_period': true},
      });
      expect(shell.topicTrackingRevisionFor(_site), greaterThan(revision));
    },
  );

  test('cleanup-listener dismissal cannot enter successor tracking', () async {
    final api = _ReplacementUserApi();
    final shell = _shell(api: api);
    addTearDown(shell.dispose);
    addTearDown(() {
      if (!api.response.isCompleted) api.response.complete(_reader);
    });
    await shell.load();
    await api.started.future;
    const row = Topic(
      id: 30,
      title: 'New topic',
      slug: 'new-topic',
      seen: false,
    );
    final route = ContentRoute.topicList(TopicListMode.newTopics);
    api.newTopicRow = row;
    shell.pushContent(route);
    await shell.loadFeed(route.id);
    expect(shell.canDismissNewTopics, isTrue);
    await shell.accountActivity.loadNotifications(shell.currentInstance!);
    expect(shell.accountActivity.notificationsFor(_site).loaded, isTrue);
    Future<String?>? dismissal;
    void dismissDuringCleanup() {
      if (dismissal != null ||
          shell.currentInstance?.user?.id != 7 ||
          shell.accountActivity.notificationsFor(_site).loaded) {
        return;
      }
      dismissal = shell.dismissNewTopics();
    }

    shell.accountActivity.addListener(dismissDuringCleanup);
    addTearDown(
      () => shell.accountActivity.removeListener(dismissDuringCleanup),
    );

    api.response.complete(const DiscourseUser(id: 8, username: 'next-reader'));
    await pumpEventQueue();

    expect(dismissal, isNotNull);
    expect(await dismissal, isNull);
    expect(shell.currentInstance?.user?.id, 8);
    expect(api.dismissNewCalls, isEmpty);
    expect(shell.store.read<Topic>(_site, 30)?.seen, isFalse);
    expect(shell.dismissingNewTopics, isFalse);
  });

  test(
    'retention acquired during attachment cannot start a partial poll',
    () async {
      final polls = <Map<String, String>>[];
      final held = Completer<http.Response>();
      final attached = <bool>[];
      final installed = PluginInstaller.install(
        PluginManifest([
          _LiveModule((host, siteUrl, channels) {
            host.retain(siteUrl);
            attached.add(true);
            channels.subscribe('/live-test/events', (_, _) {});
          }),
        ]),
      );
      final shell = _shell(
        api: FakeDiscourseApi(user: _reader),
        plugins: installed,
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
            }) => SiteTracker(
              siteUrl: siteUrl,
              onIncomingTopics: onIncomingTopics,
              onNotifications: onNotifications,
              onReviewableCounts: onReviewableCounts,
              admitIncoming: admitIncoming,
              userId: userId,
              apiKey: apiKey,
              clientId: clientId,
              shouldLongPoll: shouldLongPoll,
              initialLastIds: initialLastIds,
              httpClient: MockClient((request) {
                polls.add(request.bodyFields);
                return held.future;
              }),
            ),
      );
      addTearDown(() async {
        shell.dispose();
        if (!held.isCompleted) held.complete(http.Response('[]', 200));
        await installed.close();
      });

      await shell.load();
      await pumpEventQueue();

      expect(attached, [true]);
      expect(polls, hasLength(1));
      expect(
        polls.single.keys,
        containsAll([
          '/latest',
          '/new',
          '/notification/7',
          '/unread/7',
          '/user-status',
          '/user-drafts/7',
          '/do-not-disturb/7',
          '/live-test/events',
        ]),
      );
    },
  );

  test(
    'account refresh waits for hidden bootstrap before reading JSON',
    () async {
      final api = _FirstBootstrapGate();
      final shell = _shell(api: api);
      addTearDown(shell.dispose);
      addTearDown(() {
        if (!api.release.isCompleted) api.release.complete();
      });
      await shell.load();
      await api.started.future;
      shell.setForeground(false);
      await pumpEventQueue();

      expect(api.currentUserRequests, isEmpty);
      expect(FakeSiteTracker.built, isEmpty);
      api.release.complete();
      await pumpEventQueue();

      expect(api.currentUserRequests, isNotEmpty);
      expect(FakeSiteTracker.built, isEmpty);
      shell.setForeground(true);
      await pumpEventQueue();
      expect(FakeSiteTracker.built, hasLength(1));
      expect(FakeSiteTracker.built.single.polling, isTrue);
    },
  );

  test(
    'old blocked bootstrap cannot replace or clear a successor session',
    () async {
      final api = _FirstBootstrapGate();
      final auth = FakeAuthenticator()..keys[_site] = 'old-key';
      final shell = _shell(api: api, authenticator: auth);
      addTearDown(shell.dispose);
      addTearDown(() {
        if (!api.release.isCompleted) api.release.complete();
      });
      await shell.load();
      await api.started.future;

      shell.lifecycle.invalidate(_site);
      auth.keys[_site] = 'new-key';
      shell.setForeground(false);
      shell.setForeground(true);
      await pumpEventQueue();
      final successor = FakeSiteTracker.built.single;
      expect(successor.apiKey, 'new-key');

      api.release.complete();
      await pumpEventQueue();
      shell.setForeground(false);
      shell.setForeground(true);
      await pumpEventQueue();

      expect(FakeSiteTracker.built, [successor]);
      expect(successor.polling, isTrue);
      expect(successor.disposed, isFalse);
    },
  );

  test(
    'failed visible-topic registration closes its assembling tracker',
    () async {
      final api = _FirstBootstrapGate();
      final errors = <Object>[];
      final built = <_FailingTopicTracker>[];
      late ShellController failedShell;
      await runZonedGuarded(() async {
        final shell = _shell(
          api: api,
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
              }) {
                final tracker = _FailingTopicTracker(
                  siteUrl: siteUrl,
                  onIncomingTopics: onIncomingTopics,
                  onNotifications: onNotifications,
                  onReviewableCounts: onReviewableCounts,
                );
                built.add(tracker);
                return tracker;
              },
        );
        failedShell = shell;
        addTearDown(shell.dispose);
        await shell.load();
        await api.started.future;
        shell.pushContent(
          ContentRoute.topic(topicId: 8, slug: 'eight', title: 'Eight'),
        );
        api.release.complete();
        await pumpEventQueue();
      }, (error, _) => errors.add(error));

      expect(errors, isNotEmpty);
      expect(errors.every((error) => error is _SubscriptionFailure), isTrue);
      expect(built, hasLength(1));
      expect(built.single.disposed, isTrue);
      expect(built.single.polling, isFalse);
      final totals = failedShell.accountActivity.totalsFor(_site);
      built.single.onNotifications({'all_unread_notifications_count': 99});
      expect(failedShell.accountActivity.totalsFor(_site), totals);
    },
  );

  test('retirement during attachment closes the assembling tracker', () async {
    late ShellController shell;
    final installed = PluginInstaller.install(
      PluginManifest([
        _LiveModule((_, siteUrl, _) => shell.lifecycle.invalidate(siteUrl)),
      ]),
    );
    shell = _shell(
      api: FakeDiscourseApi(user: _reader),
      plugins: installed,
    );
    addTearDown(installed.close);
    addTearDown(shell.dispose);

    await shell.load();
    await pumpEventQueue();

    final tracker = FakeSiteTracker.built.single;
    expect(tracker.disposed, isTrue);
    expect(tracker.polling, isFalse);
    tracker.onNotifications({'all_unread_notifications_count': 99});
    expect(
      shell.accountActivity.totalsFor(_site)?.unreadNotifications,
      isNot(99),
    );
  });
}

ShellController _shell({
  required FakeDiscourseApi api,
  FakeAuthenticator? authenticator,
  InstalledPlugins? plugins,
  SiteTrackerFactory? trackers,
}) => ShellController(
  instanceStore: FakeInstanceStore([
    instance('first.example').copyWith(user: _reader),
  ]),
  api: api,
  authenticator: authenticator ?? (FakeAuthenticator()..keys[_site] = 'key'),
  drafts: FakeDraftStore(),
  trackers: trackers ?? FakeSiteTracker.reset(),
  plugins: plugins,
  updateStore: FakeUpdateStore(),
);

final class _FirstBootstrapGate extends FakeDiscourseApi {
  _FirstBootstrapGate() : super(user: _reader);
  final started = Completer<void>();
  final release = Completer<void>();
  bool _first = true;

  @override
  Future<SiteMessageBusBootstrap?> messageBusBootstrap({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    if (_first) {
      _first = false;
      started.complete();
      await release.future;
    }
    return null;
  }
}

typedef _Attach =
    void Function(
      PluginBackgroundRetentionHost host,
      String siteUrl,
      PluginLiveChannelHandle channels,
    );

final class _LiveModule implements PluginModule {
  const _LiveModule(this.attach);
  final _Attach attach;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
    id: const PluginId('live-test'),
    liveChannelScopes: {const PluginLiveChannelScope.prefix('/live-test')},
  );

  @override
  void register(PluginRegistrar registrar) {
    registrar.addLiveChannelScope(
      const PluginLiveChannelScope.prefix('/live-test'),
    );
    registrar.addSession((bindings, _) {
      final lifecycle = _LiveAttachment(
        bindings.require(corePluginBackgroundRetentionPort),
        attach,
      );
      return PluginSessionContribution(
        lifecycle: lifecycle,
        capabilities: [lifecycle],
      );
    }, requires: const [corePluginBackgroundRetentionPort]);
  }
}

final class _LiveAttachment extends PluginSessionLifecycle
    implements PluginTrackerAttachment {
  _LiveAttachment(this.host, this.attach);
  final PluginBackgroundRetentionHost host;
  final _Attach attach;

  @override
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) =>
      attach(host, siteUrl, channels);
}

final class _SubscriptionFailure implements Exception {}

final class _FailingTopicTracker extends FakeSiteTracker {
  _FailingTopicTracker({
    required super.siteUrl,
    required super.onIncomingTopics,
    required super.onNotifications,
    required super.onReviewableCounts,
  });

  @override
  void watchTopic(
    int topicId,
    List<String> channels,
    void Function(String channel, Object? data) onMessage, {
    Map<String, int?> lastIds = const {},
  }) => throw _SubscriptionFailure();
}

final class _ReplacementUserApi extends FakeDiscourseApi {
  _ReplacementUserApi() : super(user: _reader);
  final started = Completer<void>();
  final response = Completer<DiscourseUser>();
  Topic? newTopicRow;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async => TopicList(topics: [?newTopicRow]);

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    currentUserRequests.add(siteUrl);
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}
