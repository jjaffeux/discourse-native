import 'dart:async';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/site_appearance_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold start never requests account state from inactive sites', () async {
    const firstUrl = 'https://first.example';
    const secondUrl = 'https://second.example';
    final first = _connected(firstUrl).copyWith(appearance: siteAppearance());
    final second = _connected(secondUrl);
    final api = _StartupApi(firstUrl, first.appearance!);
    final authenticator = FakeAuthenticator()
      ..keys[firstUrl] = 'first-key'
      ..keys[secondUrl] = 'second-key';
    final shell = ShellController(
      instanceStore: FakeInstanceStore([first, second]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    addTearDown(shell.dispose);

    await shell.load();
    await pumpEventQueue();

    expect(api.totalsSites, [firstUrl]);
    expect(
      api.appearancesRequested,
      isEmpty,
      reason: 'persisted appearance refresh waits behind selected JSON work',
    );

    api.firstTotals.complete(const NotificationTotals());
    await pumpEventQueue();

    expect(
      api.appearancesRequested,
      isEmpty,
      reason: 'fresh persisted appearance is rendered without HTTP refresh',
    );
    expect(api.totalsSites, [firstUrl]);
    expect(
      api.totalsSites,
      isNot(contains(secondUrl)),
      reason: 'inactive sites hydrate only when the reader selects them',
    );
    expect(api.sessionSites, [firstUrl]);
    expect(api.sidebarSites, [firstUrl]);

    shell.selectInstance(1);
    await pumpEventQueue();

    expect(api.totalsSites, [firstUrl, secondUrl]);
    expect(api.sessionSites, [firstUrl, secondUrl]);
    expect(api.sidebarSites, [firstUrl, secondUrl]);

    for (var index = 0; index < 10; index++) {
      shell.selectInstance(index.isEven ? 0 : 1);
      await pumpEventQueue();
    }

    expect(api.totalsSites, [
      firstUrl,
      secondUrl,
    ], reason: 'rapid A/B switching reuses the five-minute totals snapshots');
    expect(api.sessionSites, [firstUrl, secondUrl]);
    expect(api.sidebarSites, [
      firstUrl,
      secondUrl,
    ], reason: 'an empty custom-sidebar response is still a loaded snapshot');
  });

  test(
    'restores, persists, and reconciles plugin counters on startup',
    () async {
      const siteUrl = 'https://first.example';
      final savedInstance = _connected(siteUrl).copyWith(
        notificationTotals: chatNotificationTotals(chatNotifications: 7),
      );
      final instanceStore = FakeInstanceStore([savedInstance]);
      final api = _StartupApi(siteUrl, siteAppearance());
      final authenticator = FakeAuthenticator()..keys[siteUrl] = 'key';
      final shell = ShellController(
        instanceStore: instanceStore,
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: installedPlugins,
      );
      addTearDown(shell.dispose);

      await shell.load();
      await pumpEventQueue();
      expect(shell.currentTotals?.chatNotifications, 7);

      shell.accountActivity.applyPluginCounter(
        siteUrl,
        chatNotificationCounter,
        (current) => current + 1,
      );
      await pumpEventQueue();
      expect(
        (await instanceStore.load())
            .single
            .notificationTotals
            ?.chatNotifications,
        8,
      );

      api.firstTotals.complete(chatNotificationTotals(chatNotifications: 2));
      await pumpEventQueue();
      expect(shell.currentTotals?.chatNotifications, 8);
      expect(shell.currentTotals?.hasChatEnabled, isTrue);
    },
  );

  test(
    'a different credential account cannot inherit persisted counters',
    () async {
      const siteUrl = 'https://first.example';
      final savedInstance = _connected(siteUrl).copyWith(
        notificationTotals: chatNotificationTotals(chatNotifications: 7),
      );
      final instanceStore = FakeInstanceStore([savedInstance]);
      final api = _StartupApi(
        siteUrl,
        siteAppearance(),
        sessionUser: const DiscourseUser(id: 8, username: 'other-reader'),
      );
      final authenticator = FakeAuthenticator()..keys[siteUrl] = 'key';
      final shell = ShellController(
        instanceStore: instanceStore,
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: installedPlugins,
      );
      addTearDown(shell.dispose);

      await shell.load();
      await pumpEventQueue();

      expect(shell.currentInstance?.user?.id, 8);
      expect(shell.currentTotals, isNull);
      expect(shell.currentInstance?.notificationTotals, isNull);
      expect((await instanceStore.load()).single.notificationTotals, isNull);

      api.firstTotals.complete(chatNotificationTotals(chatNotifications: 3));
      await pumpEventQueue();
      expect(shell.currentTotals, isNull);
      expect((await instanceStore.load()).single.notificationTotals, isNull);
    },
  );

  test(
    'a session response which lands after switching does not hydrate the inactive sidebar',
    () async {
      const firstUrl = 'https://first.example';
      const secondUrl = 'https://second.example';
      final first = _connected(firstUrl).copyWith(appearance: siteAppearance());
      final second = _connected(
        secondUrl,
      ).copyWith(appearance: siteAppearance());
      final api = _StartupApi(firstUrl, first.appearance!);
      final firstSession = Completer<void>();
      api.sessionGates[firstUrl] = firstSession;
      final authenticator = FakeAuthenticator()
        ..keys[firstUrl] = 'first-key'
        ..keys[secondUrl] = 'second-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([first, second]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: installedPlugins,
      );
      addTearDown(shell.dispose);

      await shell.load();
      await pumpEventQueue();
      expect(api.sessionSites, [firstUrl]);

      shell.selectInstance(1);
      await pumpEventQueue();
      expect(api.sidebarSites, [secondUrl]);

      api.firstTotals.complete(const NotificationTotals());
      firstSession.complete();
      await pumpEventQueue();
      expect(api.sidebarSites, [
        secondUrl,
      ], reason: 'the late selected-site continuation was cancelled');

      shell.selectInstance(0);
      await pumpEventQueue();
      expect(api.sidebarSites, [secondUrl, firstUrl]);
    },
  );

  test(
    'reselection hydrates chat from totals which landed while inactive',
    () async {
      const firstUrl = 'https://first.example';
      const secondUrl = 'https://second.example';
      final first = _connected(firstUrl).copyWith(appearance: siteAppearance());
      final second = _connected(
        secondUrl,
      ).copyWith(appearance: siteAppearance());
      final api = _StartupApi(firstUrl, first.appearance!);
      final authenticator = FakeAuthenticator()
        ..keys[firstUrl] = 'first-key'
        ..keys[secondUrl] = 'second-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([first, second]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: installedPlugins,
      );
      addTearDown(shell.dispose);

      await shell.load();
      await pumpEventQueue();
      shell.selectInstance(1);
      await pumpEventQueue();

      api.firstTotals.complete(chatNotificationTotals());
      await pumpEventQueue();
      expect(api.chatChannelsRequested, isNot(contains(firstUrl)));

      shell.selectInstance(0);
      await pumpEventQueue();
      expect(api.chatChannelsRequested, [firstUrl]);
    },
  );
}

DiscourseInstance _connected(String url) => DiscourseInstance(
  url: url,
  title: Uri.parse(url).host,
  apiVersion: 4,
  user: const DiscourseUser(id: 7, username: 'reader'),
);

final class _StartupApi extends FakeDiscourseApi {
  _StartupApi(
    this.firstUrl,
    SiteAppearance appearance, {
    this.sessionUser = const DiscourseUser(id: 7, username: 'reader'),
  }) : super(
         totals: const NotificationTotals(),
         siteAppearances: {firstUrl: appearance},
         chatChannelsBySite: {
           firstUrl: const ChatChannels(
             public: <ChatChannel>[],
             direct: <ChatChannel>[],
           ),
         },
       );

  final String firstUrl;
  final DiscourseUser sessionUser;
  final Completer<NotificationTotals> firstTotals = Completer();
  final List<String> totalsSites = [];
  final List<String> sessionSites = [];
  final List<String> sidebarSites = [];
  final Map<String, Completer<void>> sessionGates = {};

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    sessionSites.add(siteUrl);
    final gate = sessionGates[siteUrl];
    if (gate != null) await gate.future;
    return sessionUser;
  }

  @override
  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    sidebarSites.add(siteUrl);
    return const [];
  }

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    totalsSites.add(siteUrl);
    if (siteUrl == firstUrl) return firstTotals.future;
    return Future.value(const NotificationTotals());
  }
}
