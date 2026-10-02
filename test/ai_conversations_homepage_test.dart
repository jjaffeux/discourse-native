import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_conversations_data.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_conversations_page.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_conversations_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_conversations_service.dart';
import 'package:discourse_native/src/plugins/discourse_ai/discourse_ai_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/mobile_navigation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://example.com';
const _path = '/discourse-ai/ai-bot/conversations.json?page=0';
const _nextPath = '/discourse-ai/ai-bot/conversations.json?page=1';
final _config =
    const SiteConfig(
      defaultHomepage: 'ai-conversations',
      topMenu: ['top', 'latest'],
    ).withPlugins(
      PluginData.none.withValue(
        aiBotSettingsKey,
        const AiBotSettings(enabled: true),
      ),
    );
final _user = const DiscourseUser(id: 7, username: 'reader').withPlugins(
  PluginData.none.withValue(
    aiBotUserKey,
    const AiBotUser(hasPersonalMessageBot: true),
  ),
);

Map<String, dynamic> _page({
  int page = 0,
  bool more = false,
  List<int> ids = const [42, 43],
}) => {
  'conversations': [
    for (final id in ids)
      {
        'id': id,
        'title': 'Conversation $id',
        'slug': 'conversation-$id',
        'ai_conversation_starred': id == 42,
      },
  ],
  'meta': {'page': page, 'per_page': 40, 'has_more': more},
};

void main() {
  for (final disconnect in [false, true]) {
    testWidgets(
      'the production AI route reloads after a failed '
      '${disconnect ? 'disconnect' : 'reconnect'} restores the same account',
      (tester) async {
        final store = _FailingAccountStore();
        final api = _HeldConversationsApi();
        final setup = await _shell(store: store, conversationApi: api);
        addTearDown(setup.shell.dispose);
        await tester.pumpWidget(
          ShellScope(
            controller: setup.shell,
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                body: MainContent(layout: ShellLayout.expanded),
              ),
            ),
          ),
        );
        await _pumpProduction(tester);
        expect(find.byType(AiConversationsPage), findsOneWidget);
        final state = tester.state(find.byType(AiConversationsPage));
        final lease = setup.shell.lifecycle.capture(_site);
        expect(api.conversationReads, 1);
        expect(find.byType(DSkeletonRegion), findsOneWidget);

        store.failSignedOut = true;
        if (disconnect) {
          expect(
            await tester.runAsync(() => setup.shell.disconnectInstance(_site)),
            isFalse,
          );
        } else {
          await tester.runAsync(setup.shell.connectCurrentInstance);
        }
        expect(setup.shell.currentInstance?.user?.id, _user.id);
        expect(setup.shell.currentContent?.id, 'ai-conversations');
        expect(lease.isCurrent, isFalse);
        await _pumpProduction(tester);
        expect(tester.state(find.byType(AiConversationsPage)), same(state));

        api.first.complete(_page(ids: [42]));
        await _pumpProduction(tester);
        expect(api.conversationReads, 2);
        expect(find.text('Conversation 42'), findsNothing);
        expect(find.text('Conversation 99'), findsOneWidget);
        expect(find.byType(DSkeletonRegion), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the production AI route keeps its rows for count-only updates', (
    tester,
  ) async {
    final setup = await _shell();
    addTearDown(setup.shell.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: setup.shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: MainContent(layout: ShellLayout.expanded)),
        ),
      ),
    );
    await _pumpProduction(tester);
    final state = tester.state(find.byType(AiConversationsPage));
    final lease = setup.shell.lifecycle.capture(_site);
    FakeSiteTracker.built.last.deliverNotification(const {
      'all_unread_notifications_count': 4,
    });
    await _pumpProduction(tester);
    expect(tester.state(find.byType(AiConversationsPage)), same(state));
    expect(lease.isCurrent, isTrue);
    expect(
      setup.shell.currentInstance!.notificationTotals!.unreadNotifications,
      4,
    );
    expect(find.text('Conversation 43'), findsOneWidget);
    expect(
      setup.api.pluginReadPaths.where((path) => path == _path),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'uses the registered key for eligible connected users and round trips',
    () {
      const plugin = AiConversationsPlugin();
      expect(plugin.homepageId, 'ai-conversations');
      final route = ContentRoute.homepage(
        _config,
        connected: true,
        registeredHomepage: plugin.homepage(_config, _user),
      );
      expect(route.id, 'ai-conversations');
      expect(route.feedPath, isNull);
      expect(route.isMessages, isFalse);
      expect(TopicListMode.fromRoute(route), isNull);
      expect(ContentRoute.fromJson(route.toJson()).id, route.id);
    },
  );

  test('matches PM bot and agent permissions rather than broad AI access', () {
    expect(
      AiBotUser.fromWire({'can_use_assistant': true}).hasPersonalMessageBot,
      isFalse,
    );
    expect(
      AiBotUser.fromWire({
        'ai_enabled_chat_bots': [
          {'id': -7, 'username': 'bot'},
        ],
      }).hasPersonalMessageBot,
      isTrue,
    );
    expect(
      AiBotUser.fromWire({
        'ai_enabled_chat_bots': [
          {'id': -8, 'username': 'agent', 'is_agent': true},
        ],
      }).hasPersonalMessageBot,
      isFalse,
    );
    expect(
      AiBotUser.fromWire({
        'ai_enabled_agents': [
          {'id': 3, 'username': 'agent', 'allow_personal_messages': true},
        ],
      }).hasPersonalMessageBot,
      isTrue,
    );
    expect(
      AiBotUser.fromWire({
        'ai_enabled_agents': [
          {'username': 'agent', 'allow_personal_messages': false},
        ],
      }).hasPersonalMessageBot,
      isFalse,
    );
    expect(
      AiBotUser.fromWire({
        'ai_enabled_agents': [
          {'allow_personal_messages': true},
        ],
      }).hasPersonalMessageBot,
      isFalse,
    );
  });

  test(
    'wire and stored codecs retain availability and revoke absent permissions',
    () {
      final plugins = PluginInstaller.install(
        const PluginManifest([discourseAiModule]),
      );
      addTearDown(plugins.close);
      final models = DiscourseModelCodec(extensions: plugins.registry);
      final config = models.siteConfig({
        'discourse_ai_enabled': true,
        'ai_bot_enabled': true,
        'default_homepage': 'ai-conversations',
      }, _site);
      final user = models.currentUser({
        'id': 7,
        'username': 'reader',
        'ai_enabled_chat_bots': [
          {'id': -7, 'username': 'bot'},
        ],
      }, _site);
      expect(aiConversationsAvailable(config, user), isTrue);
      final storedUser = DiscourseUser.fromJson(
        user.toJson(extensions: plugins.registry),
        extensions: plugins.registry,
      );
      expect(aiConversationsAvailable(config, storedUser), isTrue);
      final disabled = models.siteConfig({
        'discourse_ai_enabled': true,
        'ai_bot_enabled': false,
      }, _site);
      expect(aiConversationsAvailable(disabled, user), isFalse);
      final revoked = models.preserveUnknownCurrentUser(
        user,
        models.currentUser({'id': 7, 'username': 'reader'}, _site),
      );
      expect(aiConversationsAvailable(config, revoked), isFalse);
    },
  );

  test('unavailable and anonymous homepages follow top-menu visibility', () {
    const plugin = AiConversationsPlugin();
    for (final user in [null, const DiscourseUser(username: 'reader')]) {
      expect(
        ContentRoute.homepage(
          _config,
          connected: user != null,
          registeredHomepage: plugin.homepage(_config, user),
        ).id,
        'top-yearly',
      );
    }
    final disabled = _config.withPlugins(PluginData.none);
    expect(
      ContentRoute.homepage(
        disabled,
        connected: true,
        registeredHomepage: plugin.homepage(disabled, _user),
      ).id,
      'top-yearly',
    );
    expect(
      ContentRoute.homepage(
        const SiteConfig(
          defaultHomepage: 'ai-conversations',
          topMenu: ['new', 'categories', 'latest'],
        ),
        connected: false,
      ).id,
      'all-categories',
    );
  });

  test(
    'conversation API sends credentials and reads server pagination/order',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET $_path': _page(more: true),
          'GET $_nextPath': _page(page: 1, ids: [44]),
        },
      );
      final setup = _service(transport);
      final first = await setup.service.load(_site);
      expect(first!.conversations.map((row) => row.id), [42, 43]);
      expect(first.conversations.first.starred, isTrue);
      expect(first.hasMore, isTrue);
      final next = await setup.service.load(_site, page: first.page + 1);
      expect(next!.conversations.single.id, 44);
      expect(next.hasMore, isFalse);
      expect(transport.reads.map((read) => read.path), [_path, _nextPath]);
      expect(transport.reads.first.apiKey, 'api-key');
      expect(transport.reads.first.clientId, 'test-client');
      setup.service.open(_site, next.conversations.single);
      expect(setup.navigation.currentContent?.topicId, 44);
      expect(setup.navigation.openedPost, (
        siteUrl: _site,
        topicId: 44,
        postNumber: 1,
      ));
    },
  );

  test('retired account discards an in-flight private list', () async {
    final gate = Completer<Object?>();
    final transport = RecordingPluginTransport(
      responders: {'GET $_path': (_) => gate.future},
    );
    final setup = _service(transport);
    final pending = setup.service.load(_site);
    await Future<void>.delayed(Duration.zero);
    setup.requests.lifecycle.invalidate(_site);
    gate.complete(_page());
    expect(await pending, isNull);
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('visible skeleton, pagination and PM opening at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gate = Completer<Object?>();
      final transport = RecordingPluginTransport(
        responders: {'GET $_path': (_) => gate.future},
        responses: {
          'GET $_nextPath': _page(page: 1, ids: [43, 44]),
        },
      );
      final setup = _service(transport);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: AiConversationsPage(siteUrl: _site, service: setup.service),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(find.byType(DSkeleton), findsWidgets);
      gate.complete(_page(more: true));
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.text('Conversation 42'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Conversation 43'), findsOneWidget);
      expect(find.text('Conversation 44'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      await tester.tap(find.text('Conversation 44'));
      expect(setup.navigation.currentContent?.topicId, 44);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('retry and empty state retain a usable forum fallback', (
    tester,
  ) async {
    final transport = RecordingPluginTransport(
      failures: {'GET $_path': StateError('offline')},
    );
    final setup = _service(transport);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AiConversationsPage(siteUrl: _site, service: setup.service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Couldn’t load AI conversations. Try again.'),
      findsOneWidget,
    );
    transport.failures.clear();
    transport.responses['GET $_path'] = _page(ids: []);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No AI conversations yet.'), findsOneWidget);
    await tester.tap(find.text('Browse forum'));
    expect(setup.navigation.currentContent?.id, 'top-yearly');
    expect(
      setup.navigation.currentContent?.feedPath,
      '/top.json?period=yearly',
    );
  });

  testWidgets('unavailable API displays the account fallback and hides rows', (
    tester,
  ) async {
    final transport = RecordingPluginTransport(
      failures: {
        'GET $_path': const SiteLookupException(
          SiteLookupFailure.unreachable,
          _site,
          statusCode: 404,
        ),
      },
    );
    final setup = _service(transport);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AiConversationsPage(siteUrl: _site, service: setup.service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('AI conversations are unavailable for this account.'),
      findsOneWidget,
    );
    expect(find.text('Browse forum'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets(
    'startup, PM return, Voice return and homepage selection use AI',
    (tester) async {
      final setup = await _shell();
      addTearDown(setup.shell.dispose);
      await tester.pumpWidget(
        ShellScope(
          controller: setup.shell,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: MainContent(layout: ShellLayout.expanded),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.id, 'ai-conversations');
      expect(setup.api.feedPaths, isNot(contains('/latest.json')));
      expect(find.text('Conversation 42'), findsOneWidget);
      await tester.tap(find.text('Conversation 42'));
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.topicId, 42);
      expect(setup.shell.currentTopic?.privateMessage, isTrue);
      expect(setup.shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.id, 'ai-conversations');
      setup.shell.pushContent(
        const ContentRoute(
          id: 'voice-room-5',
          title: 'Voice room',
          icon: DIcons.microphoneLines,
        ),
      );
      expect(setup.shell.handleBack(), isTrue);
      expect(setup.shell.currentContent?.id, 'ai-conversations');
      expect(setup.shell.openCorePageUrl('$_site/latest'), isTrue);
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.id, 'latest');
      setup.shell.selectDestination(
        setup.shell.currentInstance!.defaultDestination,
      );
      await tester.pumpAndSettle();
      expect(setup.shell.currentContent?.id, 'ai-conversations');
      expect(setup.shell.openCorePageUrl('$_site/latest'), isTrue);
      expect(setup.shell.openCorePageUrl('$_site/'), isTrue);
      expect(setup.shell.currentContent?.id, 'ai-conversations');
      expect(tester.takeException(), isNull);
    },
  );

  test('fresh account eligibility replaces old startup snapshots', () async {
    final setup = await _shell(
      storedUser: const DiscourseUser(id: 7, username: 'reader'),
    );
    addTearDown(setup.shell.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(setup.shell.currentContent?.id, 'ai-conversations');
    expect(setup.api.feedPaths, isNot(contains('/latest.json')));
  });

  test('explicit navigation survives a late homepage response', () async {
    final gate = Completer<void>();
    final setup = await _shell(configGate: gate);
    addTearDown(setup.shell.dispose);
    setup.shell.openCorePageUrl('$_site/latest');
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(setup.shell.currentContent?.id, 'latest');
  });

  for (final mobile in [false, true]) {
    test(
      'Voice navigation preserves the AI homepage with mobile=$mobile',
      () async {
        final setup = await _shell(mobile: mobile, voice: true);
        addTearDown(setup.shell.dispose);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (mobile) {
          setup.shell.selectMobileDestination(
            MobileTab.topics,
            setup.shell.currentInstance!.defaultDestination,
          );
        }
        expect(setup.shell.currentContent?.id, 'ai-conversations');
        setup.shell.pluginSession
            .require(voiceShellService)
            .openRoom(
              siteUrl: _site,
              route: const ContentRoute(
                id: 'voice-room-5',
                title: 'Room',
                icon: DIcons.microphoneLines,
              ),
            );
        expect(setup.shell.currentContent?.id, 'voice-room-5');
        await setup.shell.pluginSession.require(voiceControllerService).leave();
        expect(setup.shell.handleBack(), isTrue);
        expect(setup.shell.currentContent?.id, 'ai-conversations');
      },
    );
  }

  test('registered conversation URLs open the Native list', () async {
    final setup = _service(RecordingPluginTransport());
    expect(
      await setup.service.openPluginUrl(
        '$_site/discourse-ai/ai-bot/conversations',
      ),
      isTrue,
    );
    expect(setup.navigation.currentContent?.id, 'ai-conversations');
    expect(
      await setup.service.openPluginUrl(
        'https://unconnected.example/discourse-ai/ai-bot/conversations',
      ),
      isFalse,
    );
  });

  testWidgets('refresh retry repeats page zero and keeps existing rows', (
    tester,
  ) async {
    final transport = RecordingPluginTransport(
      responses: {'GET $_path': _page(more: true)},
    );
    final setup = _service(transport);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AiConversationsPage(siteUrl: _site, service: setup.service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    transport.failures['GET $_path'] = StateError('offline');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Conversation 42'), findsOneWidget);
    transport.failures.clear();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(transport.reads.map((read) => read.path), [_path, _path, _path]);
  });

  test('cold plugin-pane return resolves the configured homepage', () async {
    final setup = await _shell();
    addTearDown(setup.shell.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    setup.shell.deactivatePluginPane(const PluginId('voice'));
    expect(setup.shell.currentContent?.id, 'ai-conversations');
  });
}

({
  AiConversationsService service,
  _Navigation navigation,
  FakePluginRequestHost requests,
})
_service(RecordingPluginTransport transport) {
  final navigation = _Navigation();
  final credentials = FakeApiCredentialReader()..keys[_site] = 'api-key';
  final requests = FakePluginRequestHost(credentials: credentials);
  final service = AiConversationsService(
    transport: transport,
    requests: requests,
    siteState: PluginSiteStateHost(
      currentUserFor: (_) => _user,
      siteConfigFor: (_) => _config,
    ),
    navigation: navigation,
    topicLists: navigation,
  );
  return (service: service, navigation: navigation, requests: requests);
}

class _Navigation
    implements PluginRouteNavigationHost, PluginTopicListNavigationHost {
  @override
  String? get activeTabId => null;

  @override
  List<PluginRouteSite> get sites => [currentSite];
  @override
  PluginRouteSite get currentSite =>
      const PluginRouteSite(url: _site, title: 'Forum', isConnected: true);
  @override
  ContentRoute? currentContent;
  ({String siteUrl, int topicId, int postNumber})? openedPost;
  @override
  void selectInstance(int index) {}
  @override
  void pushContent(ContentRoute route) => currentContent = route;
  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;
  @override
  void openTopicList(ContentRoute route) => currentContent = route;
  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) {
    openedPost = (siteUrl: siteUrl, topicId: topicId, postNumber: postNumber);
  }
}

Future<({ShellController shell, FakeDiscourseApi api})> _shell({
  DiscourseUser? storedUser,
  Completer<void>? configGate,
  bool mobile = false,
  bool voice = false,
  FakeInstanceStore? store,
  FakeDiscourseApi? conversationApi,
}) async {
  final plugins = PluginInstaller.install(
    PluginManifest([
      discourseAiModule,
      if (voice) ChatModule(apiFactory: (transport) => transport as ChatApi),
      if (voice) const VoiceModule.withoutDiagnostics(),
    ]),
  );
  addTearDown(plugins.close);
  final site = instance('example.com').copyWith(
    user: storedUser ?? _user,
    config: configGate == null ? _config : const SiteConfig.unknown(),
  );
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final api =
      conversationApi ??
      FakeDiscourseApi(
        user: _user,
        siteConfigs: {_site: _config},
        siteConfigGate: configGate,
        pluginResponses: {'GET $_path': _page()},
        feeds: {'/latest.json': [], '/top.json?period=yearly': []},
        topics: {
          42: (
            detail: const TopicDetail(
              id: 42,
              title: 'Conversation 42',
              stream: [420],
              privateMessage: true,
            ),
            posts: [
              const Post(
                id: 420,
                postNumber: 1,
                username: 'bot',
                cooked: '<p>A useful answer.</p>',
              ),
            ],
          ),
        },
      );
  final shell = ShellController(
    instanceStore: store ?? FakeInstanceStore([site]),
    api: api,
    authenticator: authenticator,
    plugins: plugins,
    trackers: FakeSiteTracker.reset(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: false,
    mobileNavigationEnabled: mobile,
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await shell.load();
  return (shell: shell, api: api);
}

Future<void> _pumpProduction(WidgetTester tester) async {
  // The intentionally held initial request leaves an animated skeleton visible.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

class _FailingAccountStore extends FakeInstanceStore {
  _FailingAccountStore()
    : super([instance('example.com').copyWith(user: _user, config: _config)]);

  bool failSignedOut = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot storage unavailable'));
    }
    return super.save(instances);
  }
}

class _HeldConversationsApi extends FakeDiscourseApi {
  _HeldConversationsApi()
    : super(
        user: _user,
        siteConfigs: {_site: _config},
        feeds: {'/latest.json': [], '/top.json?period=yearly': []},
      );

  final first = Completer<Map<String, dynamic>>();
  int conversationReads = 0;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) {
    if (path == _path) {
      pluginReadPaths.add(path);
      return ++conversationReads == 1
          ? first.future
          : Future.value(_page(ids: [99]));
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
