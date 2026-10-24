import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/current_user_reconciler.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/live_channels.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/shell/site_live_sessions.dart';
import 'package:discourse_native/src/shell/topic_tracking_directory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://forum.example';
const _reader = DiscourseUser(id: 7, username: 'reader');

void main() {
  test(
    'headless anonymous public session never reads stored credentials',
    () async {
      final fixture = _Fixture(user: null);
      addTearDown(fixture.dispose);
      await fixture.start();

      final tracker = FakeSiteTracker.built.single;
      expect(tracker.polling, isTrue);
      expect(tracker.apiKey, isNull);
      expect(tracker.userId, isNull);
      expect(fixture.credentials.keyReads, 0);
      expect(fixture.credentials.clientReads, 0);
      expect(fixture.api.messageBusBootstrapRequests, isEmpty);
      expect(tracker.pluginChannelCallbacks, isEmpty);
    },
  );

  test('retention cannot open a signed-out private forum', () async {
    final fixture = _Fixture(user: null, loginRequired: true);
    addTearDown(fixture.dispose);
    fixture.foreground = false;
    fixture.retained = true;
    await fixture.start();

    expect(FakeSiteTracker.built, isEmpty);
    expect(fixture.credentials.keyReads, 0);
    expect(fixture.sessions.starting(_site), isNull);
  });

  test('latest demand stops and resumes one ready tracker', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.start();
    final tracker = FakeSiteTracker.built.single;
    expect(tracker.watchedTopic, 42);

    fixture.foreground = false;
    fixture.sessions.synchronize();
    expect(tracker.polling, isFalse);
    fixture.retained = true;
    fixture.sessions.synchronize();
    expect(tracker.polling, isTrue);
    final visibleSyncs = fixture.visibleSyncs;
    fixture.sessions.resume(resyncTracking: false);
    expect(tracker.pollNowCalls, 1);
    expect(fixture.visibleSyncs, visibleSyncs);

    fixture.selected = false;
    fixture.sessions.synchronize();
    expect(tracker.watchedTopic, isNull);
    fixture.selected = true;
    fixture.foreground = true;
    fixture.sessions.synchronize();
    expect(tracker.watchedTopic, 42);
    expect(FakeSiteTracker.built, [tracker]);
  });

  test('reentrant attachment registers every channel before polling', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.onAttach = (channels) {
      final assembling = fixture.sessions.trackerFor(_site)! as FakeSiteTracker;
      expect(assembling.polling, isFalse);
      fixture.retained = true;
      fixture.sessions.synchronize();
      expect(assembling.polling, isFalse);
      channels.subscribe('/owner-test/events', (_, _) {});
    };
    await fixture.start();

    final tracker = FakeSiteTracker.built.single;
    expect(tracker.polling, isTrue);
    expect(
      tracker.pluginChannelCallbacks.keys,
      containsAll([
        '/user-status',
        '/refresh-sidebar-sections',
        '/user-drafts/7',
        '/do-not-disturb/7',
        '/owner-test/events',
      ]),
    );
    expect(tracker.watchedTopic, 42);
  });

  test(
    'retirement during attachment closes the assembling connection',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.onAttach = (_) => fixture.lifecycle.invalidate(_site);
      await fixture.start();
      final tracker = FakeSiteTracker.built.single;

      expect(tracker.disposed, isTrue);
      expect(tracker.polling, isFalse);
      expect(fixture.sessions.trackerFor(_site), isNull);
      tracker.deliverNotification({'unread': 99});
      tracker.deliverReviewableCounts({'reviewable_count': 99});
      tracker.deliverPluginMessage('/user-status', {'id': 7});
      expect(fixture.messages, isEmpty);
    },
  );

  test('credential completion cannot replace the successor startup', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    final held = Completer<String?>();
    fixture.credentials.firstKey = held;
    fixture.sessions.synchronize();
    final oldStartup = fixture.sessions.starting(_site)!;
    expect(fixture.credentials.keyReads, 1);

    fixture.lifecycle.invalidate(_site);
    fixture.credentials.key = 'new-key';
    await fixture.start();
    final successor = FakeSiteTracker.built.single;
    held.complete('old-key');
    await oldStartup;
    await pumpEventQueue();

    expect(successor.apiKey, 'new-key');
    expect(successor.polling, isTrue);
    expect(successor.disposed, isFalse);
    expect(fixture.sessions.trackerFor(_site), same(successor));
    expect(FakeSiteTracker.built, [successor]);
  });

  test('hidden bootstrap settles without constructing a tracker', () async {
    final api = _Api()..firstBootstrap = Completer<SiteMessageBusBootstrap?>();
    final fixture = _Fixture(api: api);
    addTearDown(fixture.dispose);
    fixture.sessions.synchronize();
    final startup = fixture.sessions.starting(_site)!;
    await pumpEventQueue();
    expect(api.messageBusBootstrapRequests, [_site]);
    fixture.foreground = false;
    fixture.sessions.synchronize();
    api.firstBootstrap!.complete(null);
    await startup;
    expect(FakeSiteTracker.built, isEmpty);

    fixture.foreground = true;
    await fixture.start();
    expect(FakeSiteTracker.built.single.polling, isTrue);
  });

  test('blocked bootstrap cannot publish into a successor session', () async {
    final api = _Api()..firstBootstrap = Completer<SiteMessageBusBootstrap?>();
    final fixture = _Fixture(api: api);
    addTearDown(fixture.dispose);
    fixture.sessions.synchronize();
    final startup = fixture.sessions.starting(_site)!;
    await pumpEventQueue();
    fixture.lifecycle.invalidate(_site);
    await fixture.start();
    final successor = FakeSiteTracker.built.single;
    api.firstBootstrap!.complete(_bootstrap());
    await startup;

    expect(fixture.bootstraps, isEmpty);
    expect(fixture.sessions.trackerFor(_site), same(successor));
    expect(successor.disposed, isFalse);
  });

  test(
    'same-lease account change reconnects and rejects old callbacks',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      await fixture.start();
      final original = FakeSiteTracker.built.single;
      final lease = fixture.lifecycle.capture(_site);
      final finish = fixture.tracking.beginAccountChange(_site);
      fixture.site = fixture.site.copyWith(
        user: const DiscourseUser(id: 8, username: 'next'),
      );
      finish();
      fixture.sessions.accountChanged(_site, lease);
      await pumpEventQueue();

      final successor = FakeSiteTracker.built.last;
      expect(lease.isCurrent, isTrue);
      expect(original.disposed, isTrue);
      expect(successor.userId, 8);
      expect(successor.polling, isTrue);
      original.deliverNotification({'unread': 99});
      expect(fixture.messages, isEmpty);
      successor.deliverNotification({'unread': 1});
      expect(fixture.messages, [SiteLiveMessage.notifications]);
    },
  );

  test(
    'failed snapshot retries with its held credentials and original account',
    () async {
      final api = _Api()..failTracking = true;
      final fixture = _Fixture(api: api);
      addTearDown(fixture.dispose);
      await fixture.start();
      expect(api.trackingKeys, ['key']);
      fixture.credentials.key = 'different-key';
      api.failTracking = false;
      fixture.sessions.retryTracking(_site);
      await pumpEventQueue();

      expect(api.trackingKeys, ['key', 'key']);
      expect(fixture.tracking.existing(_site)!.reconciler.hasSnapshot, isTrue);
      expect(fixture.credentials.keyReads, 1);
    },
  );

  test('retired snapshot retry cannot enter a replacement account', () async {
    final api = _Api()..failTracking = true;
    final fixture = _Fixture(api: api);
    addTearDown(fixture.dispose);
    await fixture.start();
    final finish = fixture.tracking.beginAccountChange(_site);
    fixture.site = fixture.site.copyWith(
      user: const DiscourseUser(id: 8, username: 'next'),
    );
    finish();
    api.failTracking = false;
    fixture.sessions.retryTracking(_site);
    await pumpEventQueue();

    expect(api.trackingKeys, ['key']);
    expect(fixture.tracking.capture(_site)!.reconciler.hasSnapshot, isFalse);
  });
}

SiteMessageBusBootstrap _bootstrap() => SiteMessageBusBootstrap(
  currentUser: _reader,
  currentUserState: null,
  topicTrackingState: null,
  topicTrackingLastIds: const {},
  notificationChannelPosition: null,
);

final class _Fixture implements SiteLiveCurrentUsers, SiteLiveComposition {
  _Fixture({
    DiscourseUser? user = _reader,
    bool loginRequired = false,
    _Api? api,
  }) : site = DiscourseInstance(
         url: _site,
         title: 'Forum',
         user: user,
         loginRequired: loginRequired,
       ),
       api = api ?? _Api() {
    tracking = TopicTrackingDirectory(
      lifecycle: lifecycle,
      store: Store(),
      models: const DiscourseModelCodec.core(),
      userFor: (_) => site.user,
      configFor: (_) => site.config,
      changed: (_) {},
    );
    sessions = SiteLiveSessions(
      lifecycle: lifecycle,
      credentials: credentials,
      api: this.api,
      trackers: FakeSiteTracker.reset(),
      topicTracking: tracking,
      currentUsers: this,
      composition: this,
      demandSnapshot: () => {
        _site: SiteLiveDemand(
          foreground: foreground,
          selected: selected,
          connected: site.isConnected,
          loginRequired: site.loginRequired,
          retained: retained,
        ),
      },
    );
  }

  final lifecycle = SiteLifecycle();
  final credentials = _Credentials();
  final _Api api;
  late final TopicTrackingDirectory tracking;
  late final SiteLiveSessions sessions;
  DiscourseInstance site;
  bool foreground = true;
  bool selected = true;
  bool retained = false;
  int visibleSyncs = 0;
  final messages = <SiteLiveMessage>[];
  final bootstraps = <SiteMessageBusBootstrap>[];
  void Function(PluginLiveChannelHandle)? onAttach;
  CurrentUserReconciler? _userReconciler;
  Object? _userSession;

  Future<void> start() async {
    sessions.synchronize();
    await sessions.starting(_site);
    await pumpEventQueue();
  }

  void dispose() {
    sessions.dispose();
    tracking.dispose();
    _userReconciler?.retire();
  }

  @override
  DiscourseInstance? instanceAt(String siteUrl) =>
      siteUrl == _site ? site : null;

  @override
  CurrentUserReconciler reconcilerFor(String siteUrl) {
    final lease = lifecycle.capture(siteUrl);
    if (!identical(_userSession, lease.session)) {
      _userReconciler?.retire();
      _userSession = lease.session;
      _userReconciler = CurrentUserReconciler(
        lease: lease,
        models: const DiscourseModelCodec.core(),
      );
    }
    return _userReconciler!;
  }

  @override
  DiscourseUser? acceptSnapshot(
    String siteUrl,
    DiscourseUser user,
    SiteLease lease,
    CurrentUserSnapshot ticket,
  ) {
    final accepted = reconcilerFor(
      siteUrl,
    ).reconcile(ticket, previous: site.user, incoming: user);
    if (accepted == null || !lease.isCurrent) return null;
    site = site.copyWith(user: accepted.user);
    return accepted.user;
  }

  @override
  Future<int?> accountId(
    String siteUrl, {
    required String apiKey,
    required SiteLease lease,
  }) async => site.user?.id;

  @override
  void acceptMessage(
    String siteUrl,
    SiteLease lease,
    SiteLiveMessage kind,
    Object? data,
  ) => messages.add(kind);

  @override
  void bootstrapReceived(String siteUrl, SiteMessageBusBootstrap bootstrap) =>
      bootstraps.add(bootstrap);

  @override
  void changed(String siteUrl, SiteLiveChange change) {}

  @override
  void trackIncomingLists(String siteUrl) {}

  @override
  void synchronizeVisibleTopics(String siteUrl, SiteTracker tracker) {
    visibleSyncs++;
    tracker.watchTopic(42, ['/topic/42'], (_, _) {});
  }

  @override
  Iterable<SiteLivePluginAttachment> get pluginAttachments => [
    (
      scopes: {const PluginLiveChannelScope.prefix('/owner-test')},
      attach: (_, channels) => onAttach?.call(channels),
    ),
  ];
}

final class _Credentials implements ApiCredentialReader {
  String key = 'key';
  int keyReads = 0;
  int clientReads = 0;
  Completer<String?>? firstKey;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    keyReads++;
    if (keyReads == 1 && firstKey != null) return firstKey!.future;
    return key;
  }

  @override
  Future<String> clientId() async {
    clientReads++;
    return 'client';
  }
}

final class _Api extends FakeDiscourseApi {
  Completer<SiteMessageBusBootstrap?>? firstBootstrap;
  bool failTracking = false;
  final trackingKeys = <String>[];

  @override
  Future<SiteMessageBusBootstrap?> messageBusBootstrap({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    messageBusBootstrapRequests.add(siteUrl);
    if (messageBusBootstrapRequests.length == 1 && firstBootstrap != null) {
      return firstBootstrap!.future;
    }
    return null;
  }

  @override
  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    trackingKeys.add(apiKey);
    if (failTracking) throw StateError('tracking unavailable');
    return TopicTrackingState();
  }
}
