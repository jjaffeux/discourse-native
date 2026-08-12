import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/site_presentation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/site_appearance_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const site = 'https://meta.example';

  test('loads, publishes, persists, and caches site appearance', () async {
    final api = _PresentationApi();
    final credentials = _Credentials();
    final stored = siteAppearance(accent: const Color(0xFF112233));
    final fetched = siteAppearance(accent: const Color(0xFF445566));
    api.appearance = fetched;
    final persisted = <(String, SiteAppearance)>[];
    final controller = _controller(
      api,
      credentials: credentials,
      persistedAppearances: {site: stored},
      onAppearanceLoaded: (siteUrl, appearance) async {
        persisted.add((siteUrl, appearance));
      },
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(controller.appearanceFor(site), stored);
    await Future.wait([
      controller.refreshAppearance(site),
      controller.refreshAppearance(site),
    ]);

    expect(api.appearanceCalls, 1);
    expect(credentials.apiKeySites, [site]);
    expect(credentials.clientIdCalls, 1);
    expect(controller.appearanceFor(site), fetched);
    expect(persisted, [(site, fetched)]);
    expect(notifications, 1);

    await controller.ensureAppearance(site);
    expect(api.appearanceCalls, 1);
    controller.dispose();
  });

  test('warm persisted appearance causes no churn or request', () async {
    final appearance = siteAppearance();
    final api = _PresentationApi()..appearance = appearance;
    var persistenceCalls = 0;
    final controller = _controller(
      api,
      persistedAppearances: {site: appearance},
      onAppearanceLoaded: (_, _) async => persistenceCalls++,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.ensureAppearance(site);

    expect(controller.appearanceFor(site), appearance);
    expect(api.appearanceCalls, 0);
    expect(notifications, 0);
    expect(persistenceCalls, 0);
    controller.dispose();
  });

  test(
    'failed appearance refresh keeps persisted colors and bounds retries',
    () async {
      final stored = siteAppearance(accent: const Color(0xFF112233));
      final api = _PresentationApi()..appearanceError = StateError('offline');
      var persistenceCalls = 0;
      final controller = _controller(
        api,
        persistedAppearances: {site: stored},
        persistedFreshness: Duration.zero,
        onAppearanceLoaded: (_, _) async => persistenceCalls++,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      for (var attempt = 0; attempt < 5; attempt++) {
        await controller.ensureAppearance(site);
      }

      expect(api.appearanceCalls, 3);
      expect(controller.appearanceFor(site), stored);
      expect(persistenceCalls, 0);
      expect(notifications, 0);

      controller.forget(site);
      await controller.ensureAppearance(site);

      expect(api.appearanceCalls, 4);
      expect(controller.appearanceFor(site), stored);
      expect(persistenceCalls, 0);
      expect(notifications, 0);
      controller.dispose();
    },
  );

  test('site invalidation rejects a late appearance response', () async {
    final api = _PresentationApi();
    final gate = Completer<SiteAppearance?>();
    api.appearanceGate = gate;
    final lifecycle = SiteLifecycle();
    final persisted = <SiteAppearance>[];
    final controller = _controller(
      api,
      lifecycle: lifecycle,
      onAppearanceLoaded: (_, appearance) async {
        persisted.add(appearance);
      },
    );

    final pending = controller.ensureAppearance(site);
    await api.appearanceRequestStarted.future;
    lifecycle.invalidate(site);
    controller.forget(site);
    gate.complete(siteAppearance());
    await pending;

    expect(controller.appearanceFor(site), isNull);
    expect(persisted, isEmpty);
    controller.dispose();
  });

  test('loads, publishes, persists, and caches site config', () async {
    final api = _PresentationApi();
    final credentials = _Credentials();
    const stored = SiteConfig(emojiSet: 'apple');
    const fetched = SiteConfig(emojiSet: 'google', mainReaction: '+1');
    api.config = fetched;
    final persisted = <(String, SiteConfig)>[];
    final controller = _controller(
      api,
      credentials: credentials,
      persisted: {site: stored},
      onConfigLoaded: (siteUrl, config) async {
        persisted.add((siteUrl, config));
      },
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    final initialPresentation = controller.presentationTokenFor(site);

    expect(controller.configFor(site), stored);
    await Future.wait([
      controller.refreshConfig(site),
      controller.refreshConfig(site),
    ]);

    expect(api.configCalls, 1);
    expect(credentials.apiKeySites, [site]);
    expect(credentials.clientIdCalls, 1);
    expect(controller.configFor(site), fetched);
    expect(
      controller.presentationTokenFor(site),
      isNot(same(initialPresentation)),
    );
    expect(persisted, [(site, fetched)]);
    expect(notifications, 1);

    await controller.ensureConfig(site);
    expect(api.configCalls, 1);
    controller.dispose();
  });

  test('resolves fetched all-default config as known', () async {
    final api = _PresentationApi()..config = const SiteConfig();
    final controller = _controller(api);

    final resolved = await Future.wait([
      controller.resolveConfig(site),
      controller.resolveConfig(site),
    ]);

    expect(api.configCalls, 1);
    expect(resolved, everyElement(const SiteConfig()));
    controller.dispose();
  });

  test('does not present fallback defaults as resolved config', () async {
    final api = _PresentationApi()..configError = StateError('offline');
    final controller = _controller(api);

    final resolved = await controller.resolveConfig(site);

    expect(resolved, isNull);
    expect(controller.configFor(site), const SiteConfig.unknown());
    controller.dispose();
  });

  test(
    'warm persisted presentation makes no request until freshness expires',
    () async {
      var now = DateTime.utc(2026, 8, 11, 12);
      final api = _PresentationApi()
        ..appearance = siteAppearance(accent: const Color(0xFF445566))
        ..config = const SiteConfig(emojiSet: 'google');
      final credentials = _Credentials();
      final controller = _controller(
        api,
        credentials: credentials,
        persisted: const {site: SiteConfig(emojiSet: 'apple')},
        persistedAppearances: {
          site: siteAppearance(accent: const Color(0xFF112233)),
        },
        clock: () => now,
      );

      await Future.wait([
        controller.ensureAppearance(site),
        controller.ensureAppearance(site),
        controller.ensureConfig(site),
        controller.ensureConfig(site),
      ]);

      expect(api.appearanceCalls, 0);
      expect(api.configCalls, 0);
      expect(credentials.apiKeySites, isEmpty);
      expect(credentials.clientIdCalls, 0);

      now = now.add(
        SitePresentationController.defaultPersistedFreshness +
            const Duration(seconds: 1),
      );
      await Future.wait([
        controller.ensureAppearance(site),
        controller.ensureAppearance(site),
        controller.ensureConfig(site),
        controller.ensureConfig(site),
      ]);

      expect(api.appearanceCalls, 1);
      expect(api.configCalls, 1);
      expect(credentials.apiKeySites, [site, site]);
      expect(credentials.clientIdCalls, 2);
      controller.dispose();
    },
  );

  test('unknown persisted config still loads on first ensure', () async {
    final api = _PresentationApi()
      ..config = const SiteConfig(emojiSet: 'google');
    final controller = _controller(
      api,
      persisted: const {site: SiteConfig.unknown()},
    );

    await controller.ensureConfig(site);

    expect(api.configCalls, 1);
    expect(controller.configFor(site).emojiSet, 'google');
    controller.dispose();
  });

  test('forget invalidates warm persisted presentation', () async {
    final api = _PresentationApi()
      ..appearance = siteAppearance(accent: const Color(0xFF445566))
      ..config = const SiteConfig(emojiSet: 'google');
    final controller = _controller(
      api,
      persisted: const {site: SiteConfig(emojiSet: 'apple')},
      persistedAppearances: {
        site: siteAppearance(accent: const Color(0xFF112233)),
      },
    );

    await Future.wait([
      controller.ensureAppearance(site),
      controller.ensureConfig(site),
    ]);
    expect(api.appearanceCalls, 0);
    expect(api.configCalls, 0);

    controller.forget(site);
    await Future.wait([
      controller.ensureAppearance(site),
      controller.ensureConfig(site),
    ]);

    expect(api.appearanceCalls, 1);
    expect(api.configCalls, 1);
    controller.dispose();
  });

  test('bounds failed requests and forget resets the retry budget', () async {
    final api = _PresentationApi()..configError = StateError('offline');
    final controller = _controller(api);

    for (var i = 0; i < 5; i++) {
      await controller.ensureConfig(site);
    }
    expect(api.configCalls, 3);

    controller.forget(site);
    await controller.ensureConfig(site);
    expect(api.configCalls, 4);
    controller.dispose();
  });

  test('resolves custom emoji against the site that owns it', () async {
    final api = _PresentationApi()
      ..custom = {
        'party': '/uploads/party.png',
        'cdn': '//cdn.example/emoji.png',
        'full': 'https://assets.example/full.png',
      };
    final controller = _controller(api);
    const otherSite = 'https://other.example';

    await controller.ensureCustomEmojis(site);
    await controller.ensureCustomEmojis(otherSite);

    expect(
      controller.emojiUrlFor(site, 'party'),
      'https://meta.example/uploads/party.png',
    );
    expect(
      controller.emojiUrlFor(otherSite, 'party'),
      'https://other.example/uploads/party.png',
    );
    expect(
      controller.emojiUrlFor(site, 'cdn'),
      'https://cdn.example/emoji.png',
    );
    expect(
      controller.emojiUrlFor(otherSite, 'full'),
      'https://assets.example/full.png',
    );
    controller.dispose();
  });

  test(
    'emoji index refreshes autocomplete without presentation churn',
    () async {
      final api = _PresentationApi();
      final gate = Completer<List<SiteEmoji>>();
      api.emojiGate = gate;
      var presentationNotifications = 0;
      var autocompleteRefreshes = 0;
      final controller = _controller(
        api,
        onEmojiIndexChanged: () => autocompleteRefreshes++,
      );
      controller.addListener(() => presentationNotifications++);

      final first = controller.ensureEmojis(site);
      final second = controller.ensureEmojis(site);
      await api.emojiRequestStarted.future;
      gate.complete(const [
        SiteEmoji(name: 'smiley', url: 'smiley.png'),
        SiteEmoji(name: 'xsmile', url: 'xsmile.png'),
        SiteEmoji(name: 'smile', url: 'smile.png'),
        SiteEmoji(name: 'small', url: 'small.png'),
      ]);
      await Future.wait([first, second]);

      expect(api.emojiCalls, 1);
      expect(presentationNotifications, 0);
      expect(autocompleteRefreshes, 1);
      expect(controller.searchEmojis(site, 'smile'), const [
        SiteEmoji(name: 'smile', url: 'smile.png'),
        SiteEmoji(name: 'smiley', url: 'smiley.png'),
        SiteEmoji(name: 'xsmile', url: 'xsmile.png'),
      ]);
      expect(controller.searchEmojis(site, 'sm', limit: 2).length, 2);
      expect(controller.searchEmojis(site, 'sm', limit: 0), isEmpty);
      controller.dispose();
    },
  );

  test('emoji autocomplete retains only the best ordered matches', () async {
    final api = _PresentationApi()
      ..emojis = const [
        SiteEmoji(name: 'party_spark', url: '/uploads/party-spark.png'),
        SiteEmoji(name: 'sparkler', url: '/uploads/sparkler.png'),
        SiteEmoji(name: 'sparkling', url: '/images/emoji/sparkling.png'),
        SiteEmoji(name: 'spark', url: '/uploads/spark.png'),
        SiteEmoji(name: 'sparkle', url: '/images/emoji/sparkle.png'),
        SiteEmoji(name: 'sparks', url: '/images/emoji/sparks.png'),
        SiteEmoji(name: 'x_spark', url: '/uploads/x-spark.png'),
      ];
    final controller = _controller(api);
    await controller.ensureEmojis(site);

    expect(controller.searchEmojis(site, 'spark', limit: 4), const [
      SiteEmoji(name: 'spark', url: '/uploads/spark.png'),
      SiteEmoji(name: 'sparks', url: '/images/emoji/sparks.png'),
      SiteEmoji(name: 'sparkle', url: '/images/emoji/sparkle.png'),
      SiteEmoji(name: 'sparkler', url: '/uploads/sparkler.png'),
    ]);
    controller.dispose();
  });

  test(
    'site invalidation rejects a late response and forget is synchronous',
    () async {
      final api = _PresentationApi();
      final gate = Completer<SiteConfig>();
      api.configGate = gate;
      final lifecycle = SiteLifecycle();
      final persisted = <(String, SiteConfig)>[];
      final controller = _controller(
        api,
        lifecycle: lifecycle,
        onConfigLoaded: (siteUrl, config) async {
          persisted.add((siteUrl, config));
        },
      );

      final pending = controller.ensureConfig(site);
      await api.configRequestStarted.future;
      lifecycle.invalidate(site);
      controller.forget(site);
      expect(controller.configFor(site), const SiteConfig.unknown());

      gate.complete(const SiteConfig(emojiSet: 'apple'));
      await pending;

      expect(controller.configFor(site), const SiteConfig.unknown());
      expect(persisted, isEmpty);

      api
        ..configGate = null
        ..config = const SiteConfig(emojiSet: 'google');
      await controller.ensureConfig(site);
      expect(controller.configFor(site).emojiSet, 'google');
      controller.dispose();
    },
  );

  test(
    'reentrant invalidation cannot persist the previous session config',
    () async {
      final api = _PresentationApi()
        ..config = const SiteConfig(emojiSet: 'google');
      final lifecycle = SiteLifecycle();
      final persisted = <(String, SiteConfig)>[];
      final controller = _controller(
        api,
        lifecycle: lifecycle,
        onConfigLoaded: (siteUrl, config) async {
          persisted.add((siteUrl, config));
        },
      );
      var invalidated = false;
      controller.addListener(() {
        if (invalidated) return;
        invalidated = true;
        lifecycle.invalidate(site);
        controller.forget(site);
      });

      await controller.ensureConfig(site);

      expect(invalidated, isTrue);
      expect(persisted, isEmpty);
      expect(controller.configFor(site), const SiteConfig.unknown());
      controller.dispose();
    },
  );

  test('forget clears custom artwork and autocomplete index', () async {
    final api = _PresentationApi()
      ..custom = {'party': '/uploads/party.png'}
      ..emojis = const [SiteEmoji(name: 'party', url: 'party.png')];
    var autocompleteRefreshes = 0;
    final controller = _controller(
      api,
      onEmojiIndexChanged: () => autocompleteRefreshes++,
    );
    final initialPresentation = controller.presentationTokenFor(site);
    await controller.ensureCustomEmojis(site);
    final customPresentation = controller.presentationTokenFor(site);
    await controller.ensureEmojis(site);
    expect(customPresentation, isNot(same(initialPresentation)));
    expect(controller.presentationTokenFor(site), same(customPresentation));
    expect(controller.searchEmojis(site, 'party'), isNotEmpty);

    controller.forget(site);

    expect(controller.searchEmojis(site, 'party'), isEmpty);
    expect(
      controller.emojiUrlFor(site, 'party'),
      'https://meta.example/images/emoji/twitter/party.png',
    );
    expect(controller.presentationTokenFor(site), same(initialPresentation));
    expect(autocompleteRefreshes, 2);
    controller.dispose();
  });
}

SitePresentationController _controller(
  _PresentationApi api, {
  _Credentials? credentials,
  SiteLifecycle? lifecycle,
  Map<String, SiteConfig> persisted = const {},
  Map<String, SiteAppearance> persistedAppearances = const {},
  SiteAppearanceLoaded? onAppearanceLoaded,
  SiteConfigLoaded? onConfigLoaded,
  void Function()? onEmojiIndexChanged,
  Duration persistedFreshness =
      SitePresentationController.defaultPersistedFreshness,
  DateTime Function()? clock,
}) {
  return SitePresentationController(
    loadAppearance: api.loadAppearance,
    loadConfig: api.loadConfig,
    loadCustomEmojis: api.loadCustomEmojis,
    loadEmojis: api.loadEmojis,
    credentials: credentials ?? _Credentials(),
    lifecycle: lifecycle ?? SiteLifecycle(),
    readPersistedAppearance: (siteUrl) => persistedAppearances[siteUrl],
    readPersistedConfig: (siteUrl) => persisted[siteUrl],
    onAppearanceLoaded: onAppearanceLoaded ?? (_, _) async {},
    onConfigLoaded: onConfigLoaded ?? (_, _) async {},
    onEmojiIndexChanged: onEmojiIndexChanged ?? () {},
    persistedFreshness: persistedFreshness,
    clock: clock,
  );
}

final class _Credentials implements ApiCredentialReader {
  final List<String> apiKeySites = [];
  int clientIdCalls = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    apiKeySites.add(siteUrl);
    return 'key';
  }

  @override
  Future<String> clientId() async {
    clientIdCalls++;
    return 'client';
  }
}

final class _PresentationApi {
  SiteAppearance? appearance;
  Object? appearanceError;
  Completer<SiteAppearance?>? appearanceGate;
  Completer<void> appearanceRequestStarted = Completer<void>();
  int appearanceCalls = 0;

  SiteConfig config = const SiteConfig();
  Object? configError;
  Completer<SiteConfig>? configGate;
  Completer<void> configRequestStarted = Completer<void>();
  int configCalls = 0;

  Map<String, String> custom = const {};
  int customCalls = 0;

  List<SiteEmoji> emojis = const [];
  Completer<List<SiteEmoji>>? emojiGate;
  Completer<void> emojiRequestStarted = Completer<void>();
  int emojiCalls = 0;

  Future<SiteAppearance?> loadAppearance({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    appearanceCalls++;
    if (!appearanceRequestStarted.isCompleted) {
      appearanceRequestStarted.complete();
    }
    if (appearanceGate case final gate?) return gate.future;
    if (appearanceError case final error?) throw error;
    return appearance;
  }

  Future<SiteConfig> loadConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    configCalls++;
    if (!configRequestStarted.isCompleted) configRequestStarted.complete();
    if (configGate case final gate?) return gate.future;
    if (configError case final error?) throw error;
    return config;
  }

  Future<Map<String, String>> loadCustomEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    customCalls++;
    return custom;
  }

  Future<List<SiteEmoji>> loadEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    emojiCalls++;
    if (!emojiRequestStarted.isCompleted) emojiRequestStarted.complete();
    return emojiGate?.future ?? emojis;
  }
}
