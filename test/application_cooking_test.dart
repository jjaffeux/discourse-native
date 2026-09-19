import 'dart:convert';
import 'dart:io';
import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/src/data/application_cooking.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/cooking_plugin.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/cooking/cooking_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core only is empty; installed owner enables bundled behavior', () {
    final core = ApplicationCooking(
      plugins: PluginInstaller.install(const PluginManifest([])),
      service: _Service(),
    );
    expect(core.configuration.modules, isEmpty);
    final bundled = ApplicationCooking(
      plugins: PluginInstaller.install(const PluginManifest([cookingModule])),
      service: _Service(),
    );
    expect(
      bundled.configuration.modules.map((m) => m.owner),
      everyElement('cooking'),
    );
  });

  test('installation freezes declarations and projector owner', () {
    final capability = _Capability();
    final installed = PluginInstaller.install(
      PluginManifest([_Module(capability)]),
    );
    capability.owner = 'foreign';
    capability.modules.clear();
    final app = ApplicationCooking(plugins: installed, service: _Service());
    expect(capability.moduleReads, 1);
    expect(capability.profileReads, 1);
    expect(app.configuration.modules.single.owner, 'cooking-fixture');
    expect(
      () => app.request(
        siteUrl: 'https://a',
        accountId: '1',
        raw: '',
        config: const SiteConfig.unknown(),
      ),
      throwsStateError,
    );
  });

  test(
    'combined cooking and site settings capability remains discoverable',
    () {
      final capability = _Capability();
      final installed = PluginInstaller.install(
        PluginManifest([_Module(capability)]),
      );
      expect(installed.capabilities<SitePlugin>().single, same(capability));
      expect(installed.registry.plugins.single, same(capability));
      expect(
        installed.registry
            .readSiteSettings({'setting': 'ok'}, 'https://a')
            .get(_Codec.keyValue),
        'ok',
      );
      expect(installed.cookingPlugins.single, isNot(same(capability)));
    },
  );

  test(
    'oversized public request builder skips metadata and projectors',
    () async {
      final capability = _Capability();
      final app = ApplicationCooking(
        plugins: PluginInstaller.install(PluginManifest([_Module(capability)])),
        service: _Service(),
      );
      capability.owner = 'foreign'; // Any projection would throw.
      final request = app.request(
        siteUrl: 'https://a',
        accountId: '1',
        raw: 'x' * 65537,
        config: const SiteConfig.unknown(),
        mentions: {'x': Object()},
        hashtags: {'x': Object()},
        customEmoji: {'x': Object()},
      );
      expect(request.snapshot.mentions, isEmpty);
      expect(request.snapshot.pluginContext, isEmpty);
      expect((await app.cook(request)).failure, CookingFailure.inputLimit);
    },
  );

  test(
    'large independent caches select before merging and retain precedence',
    () async {
      final app = ApplicationCooking(
        plugins: PluginInstaller.install(const PluginManifest([])),
        service: _Service(),
      );
      addTearDown(app.dispose);
      final stored = CookingCachedMetadata(
        emojiDenyList: ['stored-denial'],
        oneboxes: {
          for (var i = 0; i < 150; i++) 'https://stored.test/$i': 'x' * 1000,
          'https://selected.test': 'stored',
        },
      );
      final supplied = CookingCachedMetadata(
        emojiDenyList: ['supplied-denial'],
        oneboxes: {
          for (var i = 0; i < 150; i++) 'https://supplied.test/$i': 'y' * 1000,
          'https://selected.test': 'supplied',
        },
      );
      app.ingestMetadata(app.captureUploads('https://a', '1'), stored);
      CookingRequest request(String raw, CookingCachedMetadata incoming) =>
          app.request(
            siteUrl: 'https://a',
            accountId: '1',
            raw: raw,
            config: const SiteConfig(),
            cachedMetadata: incoming,
          );
      expect(request('hello', supplied).snapshot.oneboxes, isEmpty);
      expect(request('hello', supplied).snapshot.emojiDenyList, [
        'supplied-denial',
      ]);
      expect(request('hello', CookingCachedMetadata()).snapshot.emojiDenyList, [
        'stored-denial',
      ]);
      expect(request('https://selected.test', supplied).snapshot.oneboxes, {
        'https://selected.test': 'supplied',
      });
      expect(
        request(
          'https://selected.test',
          CookingCachedMetadata(),
        ).snapshot.oneboxes,
        {'https://selected.test': 'stored'},
      );
    },
  );

  test(
    'aggregate enrichment is bounded across fields and required policy fails readably',
    () async {
      final app = ApplicationCooking(
        plugins: PluginInstaller.install(const PluginManifest([])),
        service: _Service(),
      );
      addTearDown(app.dispose);
      final values = {for (var i = 0; i < 120; i++) 'key$i': 'x' * 500};
      app.ingestMetadata(
        app.captureUploads('https://a', '1'),
        CookingCachedMetadata(
          oneboxes: values,
          avatars: values,
          primaryGroups: values,
        ),
      );
      final request = app.request(
        siteUrl: 'https://a',
        accountId: '1',
        raw: values.keys.join(' '),
        config: const SiteConfig(),
        cachedMetadata: CookingCachedMetadata(
          emojiTranslations: {'a': 'b'},
          unicodeEmoji: {'c': 'd'},
          allowedMediaOrigins: ['https://cdn.test'],
        ),
      );
      expect(
        utf8.encode(jsonEncode(request.snapshot.toJson())).length,
        lessThan(100 * 1024),
      );
      expect(request.snapshot.oneboxes, isNotEmpty);
      expect(request.snapshot.avatars, isNotEmpty);
      expect(request.snapshot.allowedMediaOrigins, ['https://cdn.test']);
      app.ingestMetadata(
        app.captureUploads('https://a', '1'),
        CookingCachedMetadata(emojiTranslations: {'a': 'x' * 70000}),
      );
      final limited = app.request(
        siteUrl: 'https://a',
        accountId: '1',
        raw: '<hello>',
        config: const SiteConfig(),
        cachedMetadata: CookingCachedMetadata(
          unicodeEmoji: {'b': 'y' * 70000},
          emojiDenyList: ['denied'],
        ),
      );
      final result = await app.cook(limited);
      expect(result.failure, CookingFailure.inputLimit);
      expect(result.html, contains('&lt;hello&gt;'));
      expect(result.requestFingerprint, limited.fingerprint);
      app.ingestMetadata(
        app.captureUploads('https://a', '1'),
        CookingCachedMetadata(
          allowedMediaOrigins: [
            for (var i = 0; i < 1000; i++) 'https://cdn.test/$i${'x' * 120}',
          ],
        ),
      );
      final listLimited = app.request(
        siteUrl: 'https://a',
        accountId: '1',
        raw: 'hello',
        config: const SiteConfig(),
      );
      expect((await app.cook(listLimited)).failure, CookingFailure.inputLimit);
      app.forget('https://a');
      expect((await app.cook(listLimited)).failure, CookingFailure.stale);
    },
  );

  test(
    'upload leases reject account races; snapshots select bounded metadata',
    () async {
      final service = _Service();
      final app = ApplicationCooking(
        plugins: PluginInstaller.install(const PluginManifest([])),
        service: service,
      );
      await app.start();
      final old = app.captureUploads('https://a', '1');
      expect(
        app.ingestUploads(old, {
          'upload://a': {'url': '/one.png'},
        }),
        isTrue,
      );
      CookingRequest request(
        String account, {
        Map<String, Object?> emoji = const {},
      }) => app.request(
        siteUrl: 'https://a',
        accountId: account,
        raw: 'hello upload://a :custom:',
        config: const SiteConfig.unknown(),
        customEmoji: emoji,
      );
      final first = request('1');
      expect(first.snapshot.uploads, isNotEmpty);
      final second = request(
        '2',
        emoji: {
          for (var i = 0; i < 10000; i++) 'unused$i': 'x' * 100,
          'custom': '/custom.png',
        },
      );
      expect(second.snapshot.uploads, isEmpty);
      expect(second.snapshot.customEmoji, {'custom': '/custom.png'});
      expect(
        second.snapshot.accountGeneration,
        greaterThan(first.snapshot.accountGeneration),
      );
      expect(
        app.ingestUploads(old, {
          'upload://a': {'url': '/secret.png'},
        }),
        isFalse,
      );
      expect((await app.cook(first)).failure, CookingFailure.stale);
      final current = app.captureUploads('https://a', '2');
      app.forget('https://a');
      expect(app.ingestUploads(current, {}), isFalse);
      await app.dispose();
      expect(app.ingestUploads(current, {}), isFalse);
      expect(service.starts, 1);
      expect(service.disposals, 1);
      expect(await app.start(), isFalse);
      expect(service.starts, 1);
    },
  );

  test('snapshot assembly has no HTTP port and freezes owner JSON', () {
    var httpClients = 0;
    HttpOverrides.runZoned(
      () {
        final app = ApplicationCooking(
          plugins: PluginInstaller.install(const PluginManifest([])),
          service: _Service(),
        );
        final mentions = <String, Object?>{'sam': true};
        final request = app.request(
          siteUrl: 'https://a',
          accountId: '1',
          raw: '@sam',
          config: const SiteConfig.unknown(),
          mentions: mentions,
        );
        mentions['sam'] = false;
        expect(request.snapshot.mentions['sam'], isTrue);
        expect(request.snapshot.provenance['knownSettings'], isEmpty);
      },
      createHttpClient: (_) {
        httpClients++;
        throw StateError('Cooking snapshot attempted HTTP');
      },
    );
    expect(httpClients, 0);
  });
}

final class _Service implements CookingServicePort {
  int starts = 0, disposals = 0;
  @override
  Future<bool> start() async {
    starts++;
    return true;
  }

  @override
  Future<CookingResult> cook(CookingRequest request) async =>
      CookingResult(html: request.raw);
  @override
  void invalidate() {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

final class _Module implements PluginModule {
  const _Module(this.capability);
  final _Capability capability;
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('cooking-fixture'));
  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(capability);
}

final class _Capability
    implements CookingPlugin, SitePlugin, SiteSettingsPlugin<String> {
  @override
  PluginDataPersistenceCodec<String> get siteSettingsCodec => const _Codec();
  @override
  String? readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      json['setting'] as String?;
  String owner = 'cooking-fixture';
  int moduleReads = 0, profileReads = 0;
  final modules = [
    CookingModule(id: 'fixture-mark', owner: 'cooking-fixture', version: '1'),
  ];
  @override
  String get name => owner;
  @override
  List<CookingModule> get cookingModules {
    moduleReads++;
    return modules;
  }

  @override
  List<CookingProfile> get cookingProfiles {
    profileReads++;
    return [];
  }

  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) {
    data.read(PluginDataKey<String>(owner: owner, name: 'setting'));
    return {};
  }
}

final class _Codec extends PluginDataPersistenceCodec<String> {
  const _Codec();
  static const keyValue = PluginDataKey<String>(
    owner: 'cooking-fixture',
    name: 'setting',
  );
  @override
  PluginDataKey<String> get key => keyValue;
  @override
  String? decode(Object? value) => value is String ? value : null;
  @override
  Object? encode(String value) => value;
}
