import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/site_basic_info.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://example.com/community';
final _user = const DiscourseUser(id: 7, username: 'reader').withPlugins(
  PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canChat: true),
  ),
);

SiteConfig _config({
  String? path = '/chat/c/general/9',
  bool anonymous = true,
  bool enabled = true,
  bool publicChannels = true,
  bool metadata = true,
}) => SiteConfig(
  defaultHomepage: 'chat',
  topMenu: const ['latest', 'categories'],
  homepageOptions: metadata ? [HomepageOption(id: 'chat', path: path)] : null,
  plugins: PluginData.none.withValue(
    chatSettingsDataKey,
    ChatSettings(
      chatEnabled: enabled,
      publicChannelsEnabled: publicChannels,
      anonymousChatAllowed: anonymous,
    ),
  ),
);

void main() {
  test('homepage metadata preserves denied, absent and changed paths', () {
    final absent = SiteConfig.fromSettings(const {'default_homepage': 'chat'});
    expect(absent.homepageOptions, isNull);
    final denied = SiteConfig.fromSettings(const {
      'default_homepage': 'chat',
      'homepage_options': [
        {'id': 'chat', 'path': null, 'server_side': false},
      ],
    });
    expect(denied.homepageOptions!.single.path, isNull);
    expect(denied, isNot(absent));
    final restored = SiteConfig.fromJson(
      jsonDecode(jsonEncode(denied.toJson())) as Map<String, dynamic>,
    );
    expect(restored, denied);
    expect(restored.homepageOptions!.single.id, 'chat');
    expect(SiteConfig.fromJson(absent.toJson()).homepageOptions, isNull);
    expect(_config(path: '/chat/c/-/10'), isNot(_config()));
    expect(
      _config().withPlugins(PluginData.none).homepageOptions!.single.path,
      '/chat/c/general/9',
    );
  });

  test('reads homepage options beside the settings', () async {
    final requested = <String>[];
    final settings = Completer<http.Response>();
    final site = Completer<http.Response>();
    final api = DiscourseApi(
      client: MockClient((request) {
        requested.add(request.url.path);
        return request.url.path.endsWith('/site/settings.json')
            ? settings.future
            : site.future;
      }),
    );
    addTearDown(api.close);

    final config = api.siteConfig(siteUrl: _site, apiKey: 'account-key');
    await pumpEventQueue();

    expect(requested, [
      '/community/site/settings.json',
      '/community/site.json',
    ]);

    settings.complete(
      http.Response(jsonEncode({'default_homepage': 'chat'}), 200),
    );
    site.complete(
      http.Response(
        jsonEncode({
          'homepage_options': [
            {'id': 'chat', 'path': '/chat/c/general/9'},
          ],
        }),
        200,
      ),
    );
    expect((await config).homepageOptions!.single.path, '/chat/c/general/9');
  });

  test(
    'loads viewer-scoped paths from site JSON with the same credentials',
    () async {
      final requests = <http.Request>[];
      final api = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/site/settings.json')
                  ? {'default_homepage': 'chat', 'emoji_set': 'apple'}
                  : {
                      'homepage_options': [
                        {'id': 'chat', 'path': '/chat/c/general/9'},
                      ],
                    },
            ),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final config = await api.siteConfig(
        siteUrl: _site,
        apiKey: 'account-key',
        clientId: 'native-client',
      );
      expect(requests.map((request) => request.url.path), [
        '/community/site/settings.json',
        '/community/site.json',
      ]);
      expect(
        requests.map((request) => request.headers['user-api-key']),
        everyElement('account-key'),
      );
      expect(config.emojiSet, 'apple');
      expect(config.homepageOptions!.single.path, '/chat/c/general/9');
    },
  );

  test(
    'unavailable metadata does not discard settings or authorize a path',
    () async {
      final api = DiscourseApi(
        client: MockClient(
          (request) async => request.url.path.endsWith('/site/settings.json')
              ? http.Response(
                  '{"default_homepage":"chat","emoji_set":"apple"}',
                  200,
                )
              : http.Response('unavailable', 403),
        ),
      );
      addTearDown(api.close);
      final config = await api.siteConfig(siteUrl: _site);
      expect(config.emojiSet, 'apple');
      expect(config.homepageOptions, isEmpty);
    },
  );

  test(
    'Chat resolves the channel destination independently of its homepage key',
    () {
      const plugin = ChatPlugin();
      for (final user in [null, _user]) {
        final route = plugin.homepage(_config(), user)!;
        expect(plugin.homepageId, 'chat');
        expect(route.id, 'chat-c-9');
        expect(route.feedPath, isNull);
        expect(ContentRoute.fromJson(route.toJson()).id, 'chat-c-9');
      }
      expect(plugin.homepage(_config(anonymous: false), null), isNull);
      expect(plugin.homepage(_config(enabled: false), _user), isNull);
      expect(plugin.homepage(_config(publicChannels: false), _user), isNull);
      expect(plugin.homepage(_config(metadata: false), _user), isNull);
      expect(plugin.homepage(_config(path: null), _user), isNull);
      final disabledUser = _user.withPlugins(
        PluginData.none.withValue(
          chatCurrentUserDataKey,
          const ChatCurrentUser(hasChatEnabled: false),
        ),
      );
      expect(plugin.homepage(_config(), disabledUser), isNull);
    },
  );

  for (final path in [
    'https://other.example/chat/c/-/9',
    '//other.example/chat/c/-/9',
    '/chat',
    '/chat/c/-/9/t/4',
    '/chat/c/-/9/5',
    '/chat/c/-/9/info/members',
    '/chat/c/-/9?other=1',
    '/chat/c/-/9#message',
  ]) {
    test('does not use an unsupported or nonlocal homepage path $path', () {
      expect(const ChatPlugin().homepage(_config(path: path), _user), isNull);
    });
  }

  for (final guest in [false, true]) {
    test(
      'subfolder ${guest ? 'guest' : 'account'} startup and root use Latest',
      () async {
        final setup = await _shell(guest: guest);
        addTearDown(setup.shell.dispose);
        await _flush();
        expect(setup.shell.currentContent?.id, 'latest');
        expect(setup.api.feedPaths, contains('/latest.json'));
        expect(setup.shell.openCorePageUrl('$_site/latest'), isTrue);
        expect(setup.shell.currentContent?.id, 'latest');
        expect(setup.shell.openCorePageUrl('$_site/'), isTrue);
        expect(setup.shell.currentContent?.id, 'latest');
      },
    );
  }

  testWidgets('guest starts at Latest and can explicitly open a Chat channel', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('org.discourse.native/notification_opens'),
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('org.discourse.native/notification_opens'),
        null,
      ),
    );
    SharedPreferences.setMockInitialValues({
      'discourse_native.panel_tutorial_dismissed': true,
    });
    final config = _config();
    await pumpShell(
      tester,
      phone,
      instances: [
        DiscourseInstance(
          url: _site,
          title: 'Community',
          apiVersion: 4,
          config: config,
        ),
      ],
      api: FakeDiscourseApi(
        siteConfigs: {_site: config},
        basicInfos: const {_site: SiteBasicInfo(title: 'Community')},
        feeds: {'/latest.json': []},
        chatChannelsBySite: const {
          _site: ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'General',
                kind: ChatChannelKind.category,
              ),
            ],
            direct: [],
          ),
        },
        chatMessagesByKey: {
          FakeDiscourseApi.chatMessagesLatestKey(9): (
            messages: [],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
          FakeDiscourseApi.chatMessagesKey(9): (
            messages: [],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      ),
      pluginManifest: PluginManifest([
        ChatModule(apiFactory: (transport) => transport as ChatApi),
      ]),
    );
    final shell = ShellScope.read(
      tester.element(find.byType(MobileForumRoot).first),
    );
    expect(shell.currentContent?.id, 'latest');
    await shell.pluginSession
        .require(chatControllerService)
        .loadChannels(_site);
    expect(
      shell.pluginSession.require(chatShellService).openChannel(9),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'chat-c-9');
    expect(find.byType(ChatChannelView), findsOneWidget);
    expect(find.text('General'), findsWidgets);
    await _capture(tester, 'guest-chat-homepage');
    await tester.tap(find.byKey(const ValueKey('mobile-home-button')));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'latest');
    expect(find.byType(ChatChannelView), findsNothing);
    await _capture(tester, 'guest-chat-homepage-topics');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test('explicit navigation survives a delayed homepage response', () async {
    final api = _HomepageApi()..nextConfig = Completer<SiteConfig>();
    final setup = await _shell(
      api: api,
      initialConfig: const SiteConfig.unknown(),
    );
    addTearDown(setup.shell.dispose);
    setup.shell.openCorePageUrl('$_site/latest');
    api.nextConfig!.complete(_config());
    await _flush();
    expect(setup.shell.currentContent?.id, 'latest');
  });

  test(
    'disconnect cannot reuse the prior account homepage while guest metadata loads',
    () async {
      final setup = await _shell();
      addTearDown(setup.shell.dispose);
      await _flush();
      expect(setup.shell.currentContent?.id, 'latest');
      setup.api.nextConfig = Completer<SiteConfig>();
      expect(await setup.shell.disconnectInstance(_site), isTrue);
      expect(setup.shell.currentContent?.id, 'latest');
      setup.api.nextConfig!.complete(_config(path: null));
      await _flush();
      expect(setup.shell.currentContent?.id, 'latest');
    },
  );

  test(
    'retired account homepage response cannot replace guest fallback',
    () async {
      final old = Completer<SiteConfig>();
      final api = _HomepageApi()..nextConfig = old;
      final setup = await _shell(
        api: api,
        initialConfig: const SiteConfig.unknown(),
      );
      addTearDown(setup.shell.dispose);
      await _flush();
      expect(api.siteConfigsRequested, isNotEmpty);
      api.nextConfig = null;
      api.config = _config(path: null);
      expect(await setup.shell.disconnectInstance(_site), isTrue);
      await _flush();
      old.complete(_config());
      await _flush();
      expect(setup.shell.currentInstance?.user, isNull);
      expect(setup.shell.currentContent?.id, 'latest');
    },
  );
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 25));

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['NATIVE_UI_EVIDENCE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<({ShellController shell, _HomepageApi api})> _shell({
  bool guest = false,
  _HomepageApi? api,
  SiteConfig? initialConfig,
}) async {
  final plugins = PluginInstaller.install(
    PluginManifest([
      ChatModule(apiFactory: (transport) => transport as ChatApi),
    ]),
  );
  addTearDown(plugins.close);
  final transport = api ?? _HomepageApi();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: _site,
        title: 'Community',
        apiVersion: 4,
        user: guest ? null : _user,
        config: initialConfig ?? _config(),
      ),
    ]),
    api: transport,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    plugins: plugins,
    trackers: FakeSiteTracker.reset(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: false,
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await shell.load();
  return (shell: shell, api: transport);
}

class _HomepageApi extends FakeDiscourseApi {
  _HomepageApi() : super(user: _user, feeds: {'/latest.json': []});

  Completer<SiteConfig>? nextConfig;
  SiteConfig config = _config();

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    siteConfigsRequested.add(siteUrl);
    return nextConfig == null ? config : await nextConfig!.future;
  }
}
