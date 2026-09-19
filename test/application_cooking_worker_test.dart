import 'dart:io';

import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/application_cooking.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/cooking_plugin.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_module.dart';
import 'package:discourse_native/src/plugins/cooking/cooking_module.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'installed native fixture cooks through host, worker and sanitizer without HTTP',
    () async {
      var httpClients = 0;
      await HttpOverrides.runZoned(
        () async {
          final installed = PluginInstaller.install(
            const PluginManifest([cookingModule, chatModule, _FixtureModule()]),
          );
          final app = ApplicationCooking(plugins: installed);
          addTearDown(app.dispose);
          addTearDown(installed.close);
          expect(await app.start(), isTrue);
          final request = app.request(
            siteUrl: 'https://a.example',
            accountId: '7',
            raw: '==TOKEN==',
            profile: CookingProfile.chat,
            config: const SiteConfig(),
          );
          final result = await app.cook(request);
          expect(result.failure, isNull);
          expect(
            result.html,
            contains('<mark data-fixture="bundled">native</mark>'),
          );
          expect(
            result.html,
            contains('<mark data-fixture="tail">tail</mark>'),
          );
          expect(result.html, isNot(contains('onclick')));
          expect(result.html, isNot(contains('<script')));
          expect(result.html, isNot(contains('javascript:')));
          expect(result.requestFingerprint, request.fingerprint);
          expect(await app.cook(request), same(result));
          app.forget('https://a.example');
          expect((await app.cook(request)).failure, CookingFailure.stale);
        },
        createHttpClient: (_) {
          httpClients++;
          throw StateError('Cooking attempted HTTP');
        },
      );
      expect(httpClients, 0);
    },
  );

  test(
    'real shell setup and teardown own cooking prewarm and disposal',
    () async {
      final service = _LifecycleService();
      final plugins = PluginInstaller.install(const PluginManifest([]));
      final shell = ShellController(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
        plugins: plugins,
        cookingService: service,
      );
      await shell.load();
      expect(service.starts, 1);
      final request = shell.cookingRequest(
        siteUrl: 'https://cold.example',
        raw: '**cold**',
      );
      expect(request.snapshot.mentions, isEmpty);
      expect(request.snapshot.hashtags, isEmpty);
      expect(request.snapshot.provenance['knownSettings'], isEmpty);
      expect(request.snapshot.provenance['staleSettings'], isTrue);
      shell.dispose();
      await shell.cooking.dispose();
      await plugins.close();
      expect(service.disposals, 1);
    },
  );
}

final class _FixtureModule implements PluginModule {
  const _FixtureModule();
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('cooking-fixture'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(_FixtureCapability());
}

final class _FixtureCapability implements CookingPlugin {
  @override
  String get name => 'cooking-fixture';
  @override
  List<CookingProfile> get cookingProfiles => const [];
  @override
  List<CookingModule> get cookingModules => [
    CookingModule(id: 'fixture-mark', owner: name, version: '1'),
    CookingModule(
      id: 'fixture-tokens',
      owner: name,
      version: '1',
      dependencies: ['fixture-mark'],
    ),
    CookingModule(
      id: 'fixture-document',
      owner: name,
      version: '1',
      dependencies: ['fixture-tokens'],
    ),
  ];
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) => {
    'replace': 'native',
    'append':
        '<mark data-fixture="tail" onclick="bad()">tail</mark><script>bad()</script><a href="javascript:bad()">bad</a>',
  };
}

final class _LifecycleService implements CookingServicePort {
  int starts = 0, disposals = 0;
  @override
  Future<bool> start() async {
    starts++;
    return true;
  }

  @override
  Future<CookingResult> cook(CookingRequest request) async =>
      CookingResult(html: request.raw).forRequest(request);
  @override
  void invalidate() {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}
