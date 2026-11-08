import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/request_intent.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_basic_info.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/site_appearance_fixtures.dart';

void main() {
  test(
    'startup warms remain background until a reader joins their held futures',
    () async {
      const site = 'https://first.example';
      final api = _IntentStartupApi();
      final shell = ShellController(
        instanceStore: FakeInstanceStore([_connected(site)]),
        api: api,
        authenticator: FakeAuthenticator()..keys[site] = 'key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: installedPlugins,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await pumpEventQueue();
      expect(api.categoryIntent?.isInteractive, isFalse);
      expect(api.catalogIntent?.isInteractive, isFalse);
      expect(api.basicInfoIntent?.isInteractive, isFalse);
      expect(RequestIntent.current.isInteractive, isTrue);

      final catalog = shell.ensureEmojiCatalog(site);
      expect(api.catalogIntent?.isInteractive, isTrue);
      expect(api.categoryIntent?.isInteractive, isFalse);
      final categories = shell.loadCategories(site);
      await pumpEventQueue();
      expect(api.categoryIntent?.isInteractive, isTrue);
      api.categoriesReady.complete();
      api.catalogReady.complete();
      await Future.wait([categories, catalog]);
      expect(api.categoryRequests, [site]);
      expect(api.emojisRequested, [site]);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold start fully hydrates only the selected site', () async {
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

    expect(api.messageBusBootstrapRequests, [
      firstUrl,
      secondUrl,
    ], reason: 'every connected live tracker needs a cursor snapshot');
    expect(api.totalsSites, [firstUrl]);
    expect(
      api.appearancesRequested,
      isEmpty,
      reason: 'persisted appearance refresh waits behind selected JSON work',
    );
    expect(api.basicInfoRequested, [
      firstUrl,
    ], reason: 'stored forum metadata is re-read on first activation only');

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
    expect(api.messageBusBootstrapRequests, [firstUrl, secondUrl]);
    expect(api.sessionSites, [firstUrl, secondUrl]);
    expect(api.sidebarSites, [firstUrl, secondUrl]);
    expect(api.basicInfoRequested, [firstUrl, secondUrl]);

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
    expect(api.messageBusBootstrapRequests, [
      firstUrl,
      secondUrl,
    ], reason: 'each live tracker needs one fresh cursor snapshot');
    expect(api.basicInfoRequested, [
      firstUrl,
      secondUrl,
    ], reason: 'each forum re-reads its metadata once per launch');
  });

  test('selected JSON refreshes wait for the cursor snapshot', () async {
    const siteUrl = 'https://first.example';
    final bootstrapGate = Completer<void>();
    final api = FakeDiscourseApi(
      totals: const NotificationTotals(),
      messageBusBootstrapGate: bootstrapGate,
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([_connected(siteUrl)]),
      api: api,
      authenticator: FakeAuthenticator()..keys[siteUrl] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: installedPlugins,
    );
    addTearDown(shell.dispose);

    await shell.load();
    await pumpEventQueue();

    expect(api.messageBusBootstrapRequests, [siteUrl]);
    expect(api.totalsCalls, 0);

    bootstrapGate.complete();
    await pumpEventQueue();

    expect(api.totalsCalls, 1);
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

  group('site notification catalog', () {
    const site = 'https://first.example';
    const pluginType = NotificationTypeName('plugin_alert');
    final withCatalog = _siteJson({
      'notification_types': {'replied': 2, 'plugin_alert': 4200},
    });

    Future<ShellController> start(
      _SiteJsonApi api, {
      FakeAuthenticator? authenticator,
      DiscourseInstance? instance,
    }) async {
      final shell = ShellController(
        instanceStore: FakeInstanceStore([instance ?? _connected(site)]),
        api: api,
        authenticator:
            authenticator ?? (FakeAuthenticator()..keys[site] = 'key'),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        plugins: installedPlugins,
      );
      addTearDown(shell.dispose);
      await shell.load();
      await pumpEventQueue();
      return shell;
    }

    test('Other reuses the site read that loaded the categories', () async {
      final api = _SiteJsonApi([withCatalog]);
      final shell = await start(api);

      await shell.loadOtherNotifications(site);

      // ignore: avoid_print
      print('PERF_PROOF site-json site_json_requests=${api.siteJsonRequests}');
      // ignore: avoid_print
      print(
        'PERF_PROOF site-json site_notification_types_calls='
        '${api.siteNotificationTypesRequested.length}',
      );
      expect(api.notificationFilters.last, contains(pluginType));
      expect(shell.accountActivity.otherNotificationsFor(site).loaded, isTrue);
      expect(api.siteJsonRequests, 1);
      expect(api.siteNotificationTypesRequested, isEmpty);
    });

    final unusableSiteReads = <String, http.Response>{
      'failed': http.Response('', 500),
      'lacked the field': _siteJson({}),
      'had an empty catalog': _siteJson({
        'notification_types': <String, int>{},
      }),
      'had a malformed catalog': _siteJson({'notification_types': 'broken'}),
    };
    for (final MapEntry(key: outcome, value: siteRead)
        in unusableSiteReads.entries) {
      test(
        'Other fetches its own catalog when the site read $outcome',
        () async {
          final api = _SiteJsonApi([siteRead, withCatalog]);
          final shell = await start(api);
          expect(api.siteJsonRequests, 1);

          await shell.loadOtherNotifications(site);

          expect(api.siteNotificationTypesRequested, [site]);
          expect(api.siteJsonRequests, 2);
          expect(api.notificationFilters.last, contains(pluginType));
          expect(
            shell.accountActivity.otherNotificationsFor(site).loaded,
            isTrue,
          );
        },
      );
    }

    test(
      'a replaced account\'s site read cannot seed the next account',
      () async {
        final oldResult = Completer<void>();
        final api = _SiteJsonApi([
          _siteJson({
            'notification_types': {'stale_alert': 9000},
          }),
          _siteJson({}),
          withCatalog,
        ])..heldCategoryResult = oldResult;
        final authenticator = FakeAuthenticator()..keys[site] = 'old-key';
        final shell = await start(api, authenticator: authenticator);
        expect(api.siteJsonRequests, 1);

        shell.lifecycle.invalidate(site);
        shell.clearAccountSessionState(site);
        authenticator.keys[site] = 'next-key';
        shell.applyAccountSessionInstance(
          shell
              .instanceFor(site)!
              .copyWith(user: const DiscourseUser(id: 8, username: 'next')),
          AccountSessionPhase.connecting,
        );
        await shell.loadCategories(site);
        expect(api.siteJsonRequests, 2);

        oldResult.complete();
        await pumpEventQueue();
        await shell.loadOtherNotifications(site);

        expect(api.siteNotificationTypesRequested, [site]);
        expect(api.siteJsonRequests, 3);
        expect(api.notificationFilters.last, contains(pluginType));
        expect(
          api.notificationFilters.last,
          isNot(contains(const NotificationTypeName('stale_alert'))),
        );
      },
    );

    test(
      'the tag editor reuses the site read that loaded the categories',
      () async {
        final api = _SiteJsonApi([_composerSite()]);
        final shell = await start(api);

        final capabilities = await shell.prepareTopicTagEditor(site);

        // ignore: avoid_print
        print(
          'PERF_PROOF composer-site-json tag_editor_site_json_requests='
          '${api.siteJsonRequests}',
        );
        // ignore: avoid_print
        print(
          'PERF_PROOF composer-site-json tag_editor_capability_reads='
          '${api.topicComposerCapabilityRequests.length}',
        );
        expect(capabilities.canTagTopics, isTrue);
        expect(capabilities.canCreateTag, isTrue);
        expect(capabilities.tagsFilterRegexp, '[/]');
        expect(capabilities.uncategorizedCategoryId, 1);
        expect(capabilities.maxTagLength, 20);
        expect(capabilities.maxTagsPerTopic, 5);
        expect(api.siteJsonRequests, 1);
        expect(api.topicComposerCapabilityRequests, isEmpty);
      },
    );

    test(
      'a new topic reuses the site read that loaded the categories',
      () async {
        const author = DiscourseUser(
          id: 7,
          username: 'reader',
          canCreateTopic: true,
        );
        final api = _SiteJsonApi([_composerSite()], user: author);
        final shell = await start(
          api,
          instance: _connected(site).copyWith(user: author),
        );

        await shell.openNewTopicFromSidebar();

        // ignore: avoid_print
        print(
          'PERF_PROOF composer-site-json new_topic_site_json_requests='
          '${api.siteJsonRequests}',
        );
        expect(shell.visibleComposer, isNotNull);
        expect(shell.topicComposerCapabilities(site).canTagTopics, isTrue);
        expect(api.siteJsonRequests, 1);
      },
    );

    test(
      'a composer fetches its own capabilities after a failed site read',
      () async {
        final api = _SiteJsonApi([http.Response('', 500), _composerSite()]);
        final shell = await start(api);
        expect(api.siteJsonRequests, 1);

        final capabilities = await shell.prepareTopicTagEditor(site);

        expect(capabilities.canTagTopics, isTrue);
        expect(api.topicComposerCapabilityRequests, [site]);
        expect(api.siteJsonRequests, 2);
      },
    );

    test('an anonymous site read cannot seed the signed-in composer', () async {
      final api = _SiteJsonApi([
        _siteJson({'can_tag_topics': false, 'max_tag_length': 7}),
        _composerSite(),
      ]);
      final shell = await start(
        api,
        instance: DiscourseInstance(
          url: site,
          title: Uri.parse(site).host,
          apiVersion: 4,
        ),
      );
      expect(api.siteJsonRequests, 1);

      shell.applyAccountSessionInstance(
        shell
            .instanceFor(site)!
            .copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
        AccountSessionPhase.connecting,
      );
      final capabilities = await shell.prepareTopicTagEditor(site);

      expect(capabilities.canTagTopics, isTrue);
      expect(capabilities.maxTagLength, 20);
      expect(api.topicComposerCapabilityRequests, [site]);
      expect(api.siteJsonRequests, 2);
    });

    test(
      'a site read landing after a composer opened keeps its answer',
      () async {
        final categoryResult = Completer<void>();
        final api = _SiteJsonApi([
          _composerSite(maxTagLength: 7),
          _composerSite(),
        ])..heldCategoryResult = categoryResult;
        final shell = await start(api);
        expect(api.siteJsonRequests, 1);

        final opened = await shell.prepareTopicTagEditor(site);
        expect(opened.maxTagLength, 20);

        categoryResult.complete();
        await pumpEventQueue();

        expect(shell.topicComposerCapabilities(site).maxTagLength, 20);
        expect(api.siteJsonRequests, 2);
      },
    );

    test(
      'a replaced account\'s site read cannot seed the next account\'s composer',
      () async {
        final oldResult = Completer<void>();
        final api = _SiteJsonApi([
          _composerSite(maxTagLength: 7),
          http.Response('', 500),
          _composerSite(),
        ])..heldCategoryResult = oldResult;
        final authenticator = FakeAuthenticator()..keys[site] = 'old-key';
        final shell = await start(api, authenticator: authenticator);
        expect(api.siteJsonRequests, 1);

        shell.lifecycle.invalidate(site);
        shell.clearAccountSessionState(site);
        authenticator.keys[site] = 'next-key';
        shell.applyAccountSessionInstance(
          shell
              .instanceFor(site)!
              .copyWith(user: const DiscourseUser(id: 8, username: 'next')),
          AccountSessionPhase.connecting,
        );
        await shell.loadCategories(site);
        expect(api.siteJsonRequests, 2);

        oldResult.complete();
        await pumpEventQueue();
        final capabilities = await shell.prepareTopicTagEditor(site);

        expect(capabilities.maxTagLength, 20);
        expect(api.topicComposerCapabilityRequests, [site]);
        expect(api.siteJsonRequests, 3);
      },
    );
  });
}

http.Response _siteJson(Map<String, Object?> body) =>
    http.Response(jsonEncode(body), 200);

http.Response _composerSite({int maxTagLength = 20}) => _siteJson({
  'can_tag_topics': true,
  'can_create_tag': true,
  'tags_filter_regexp': '[/]',
  'uncategorized_category_id': 1,
  'max_tag_length': maxTagLength,
  'max_tags_per_topic': 5,
});

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
    String? apiKey,
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

final class _IntentStartupApi extends FakeDiscourseApi {
  _IntentStartupApi()
    : super(siteConfigs: {'https://first.example': const SiteConfig()});
  RequestIntent? categoryIntent;
  RequestIntent? catalogIntent;
  RequestIntent? basicInfoIntent;
  final categoriesReady = Completer<void>();
  final catalogReady = Completer<void>();

  @override
  Future<SiteBasicInfo> basicInfo(String siteUrl) {
    basicInfoIntent = RequestIntent.current;
    return super.basicInfo(siteUrl);
  }

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    categoryIntent = RequestIntent.current;
    await categoriesReady.future;
    return super.loadCategories(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      page: page,
    );
  }

  @override
  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    catalogIntent = RequestIntent.current;
    await catalogReady.future;
    return super.emojiCatalog(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

/// Runs the category and catalog reads over the production HTTP adapter, so
/// each `/site.json` they spend is counted on the wire.
final class _SiteJsonApi extends FakeDiscourseApi {
  _SiteJsonApi(this.siteJsonAnswers, {super.user})
    : super(
        otherNotificationList: const [],
        totals: const NotificationTotals(),
      );

  /// One answer per read, the last repeating for any further reads.
  final List<http.Response> siteJsonAnswers;
  int siteJsonRequests = 0;

  /// Holds the next parsed category result on its way back to the shell, the
  /// window in which the account can be replaced.
  Completer<void>? heldCategoryResult;

  late final DiscourseApi _wire = DiscourseApi(
    client: MockClient((request) async {
      if (request.url.path != '/site.json') {
        return _siteJson({
          'category_list': {'categories': const <Object>[]},
        });
      }
      final answer =
          siteJsonAnswers[math.min(
            siteJsonRequests,
            siteJsonAnswers.length - 1,
          )];
      siteJsonRequests += 1;
      return answer;
    }),
  );

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    final hold = heldCategoryResult;
    heldCategoryResult = null;
    final result = await _wire.loadCategories(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      page: page,
    );
    await hold?.future;
    return result;
  }

  @override
  Future<List<NotificationWireType>> siteNotificationTypes({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    siteNotificationTypesRequested.add(siteUrl);
    return _wire.siteNotificationTypes(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    topicComposerCapabilityRequests.add(siteUrl);
    return _wire.topicComposerCapabilities(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
