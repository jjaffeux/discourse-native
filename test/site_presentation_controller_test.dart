import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
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

  group('SitePresentationController', () {
    group('appearance', () {
      test('refresh loads, publishes, persists, and caches values', () async {
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
      });

      test('warm persisted values cause no churn or request', () async {
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
      });

      test(
        'failed refresh keeps persisted colors and bounds retries',
        () async {
          final diagnostics = await _installDiagnostics('appearance-load');
          final stored = siteAppearance(accent: const Color(0xFF112233));
          final api = _PresentationApi()
            ..appearanceError = StateError('offline');
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
          final events = diagnostics.events.whereType<ErrorDiagnosticEvent>();
          expect(events, isNotEmpty);
          expect(
            events,
            everyElement(_isAppearanceFailure('siteAppearance.load')),
          );
        },
      );

      test('failed persistence keeps fetched colors and reports it', () async {
        final diagnostics = await _installDiagnostics('appearance-persist');
        final fetched = siteAppearance(accent: const Color(0xFF445566));
        final api = _PresentationApi()..appearance = fetched;
        final controller = _controller(
          api,
          onAppearanceLoaded: (_, _) async {
            throw StateError('storage unavailable');
          },
        );

        await controller.ensureAppearance(site);

        expect(controller.appearanceFor(site), fetched);
        expect(
          diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
          _isAppearanceFailure('siteAppearance.persist'),
        );
      });

      test('site invalidation rejects a late response', () async {
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
      });

      test(
        'reentrant disposal prevents persistence after publication',
        () async {
          final api = _PresentationApi()..appearance = siteAppearance();
          var persistenceCalls = 0;
          final controller = _controller(
            api,
            onAppearanceLoaded: (_, _) async => persistenceCalls++,
            autoDispose: false,
          );
          controller.addListener(controller.dispose);

          await controller.ensureAppearance(site);

          expect(persistenceCalls, 0);
        },
      );
    });

    group('configuration and persistence', () {
      test(
        'config refresh loads, publishes, persists, and caches values',
        () async {
          final api = _PresentationApi();
          final credentials = _Credentials();
          const stored = SiteConfig(emojiSet: 'apple');
          const fetched = SiteConfig(emojiEnabled: false, emojiSet: 'google');
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
        },
      );

      test('all-default fetched config resolves as known', () async {
        final api = _PresentationApi()..config = const SiteConfig();
        final controller = _controller(api);

        final resolved = await Future.wait([
          controller.resolveConfig(site),
          controller.resolveConfig(site),
        ]);

        expect(api.configCalls, 1);
        expect(resolved, everyElement(const SiteConfig()));
      });

      test('fallback defaults do not resolve', () async {
        final api = _PresentationApi()..configError = StateError('offline');
        final controller = _controller(api);

        final resolved = await controller.resolveConfig(site);

        expect(resolved, isNull);
        expect(controller.configFor(site), const SiteConfig.unknown());
      });

      test(
        'warm persisted values prevent requests until freshness expires',
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
        },
      );

      test('unknown persisted config loads on first ensure', () async {
        final api = _PresentationApi()
          ..config = const SiteConfig(emojiSet: 'google');
        final controller = _controller(
          api,
          persisted: const {site: SiteConfig.unknown()},
        );

        await controller.ensureConfig(site);

        expect(api.configCalls, 1);
        expect(controller.configFor(site).emojiSet, 'google');
      });

      test('forget invalidates warm persisted values', () async {
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
      });

      test(
        'failed requests are bounded and forget resets the retry budget',
        () async {
          final api = _PresentationApi()..configError = StateError('offline');
          final controller = _controller(api);

          for (var i = 0; i < 5; i++) {
            await controller.ensureConfig(site);
          }
          expect(api.configCalls, 3);

          controller.forget(site);
          await controller.ensureConfig(site);
          expect(api.configCalls, 4);
        },
      );
    });

    group('emoji metadata', () {
      test('custom URLs resolve against the site that owns them', () async {
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
      });

      test('name lookups use custom uploads and the catalog', () async {
        final api = _PresentationApi()
          ..custom = {'partyparrot': '/uploads/parrot.png'}
          ..emojis = const [
            SiteEmoji(name: 'tada', url: 'tada.png'),
            SiteEmoji(name: 'wave', url: 'wave.png', tonable: true),
            SiteEmoji(name: 'megaphone', url: 'megaphone.png'),
          ];
        final controller = _controller(api);

        expect(controller.knowsEmoji(site, 'tada'), isFalse);

        await controller.ensureCustomEmojis(site);
        expect(controller.knowsEmoji(site, 'partyparrot'), isTrue);
        expect(controller.knowsEmoji(site, 'tada'), isFalse);

        await controller.ensureEmojiCatalog(site);
        expect(controller.knowsEmoji(site, 'tada'), isTrue);
        expect(controller.knowsEmoji(site, 'wave:t3'), isTrue);
        expect(controller.emojiNameFor(site, 'mega'), 'megaphone');
        expect(controller.emojiNameFor(site, 'mega:t3'), 'megaphone:t3');
        expect(controller.knowsEmoji(site, '30'), isFalse);
        expect(controller.emojiNameFor(site, 'xray'), isNull);
        expect(controller.knowsEmoji('https://other.example', 'tada'), isFalse);
      });

      test('the index shares one request without presentation churn', () async {
        final api = _PresentationApi();
        final gate = Completer<List<SiteEmoji>>();
        api.emojiGate = gate;
        var presentationNotifications = 0;
        final controller = _controller(api);
        controller.addListener(() => presentationNotifications++);

        final first = controller.ensureEmojiCatalog(site);
        final second = controller.ensureEmojiCatalog(site);
        expect(second, same(first));
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
        expect(controller.searchEmojis(site, 'smile'), const [
          SiteEmoji(name: 'smile', url: 'smile.png'),
          SiteEmoji(name: 'smiley', url: 'smiley.png'),
          SiteEmoji(name: 'xsmile', url: 'xsmile.png'),
        ]);
        expect(controller.searchEmojis(site, 'sm', limit: 2).length, 2);
        expect(controller.searchEmojis(site, 'sm', limit: 0), isEmpty);
      });

      test('autocomplete retains only the best ordered matches', () async {
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
        await controller.ensureEmojiCatalog(site);

        expect(controller.searchEmojis(site, 'spark', limit: 4), const [
          SiteEmoji(name: 'spark', url: '/uploads/spark.png'),
          SiteEmoji(name: 'sparkle', url: '/images/emoji/sparkle.png'),
          SiteEmoji(name: 'sparkler', url: '/uploads/sparkler.png'),
          SiteEmoji(name: 'sparkling', url: '/images/emoji/sparkling.png'),
        ]);
      });

      test('search honors the picker result ceiling', () async {
        final api = _PresentationApi()
          ..emojis = [
            for (var index = 0; index < 60; index++)
              SiteEmoji(
                name: 'match_${index.toString().padLeft(2, '0')}',
                url: '$index.png',
              ),
          ];
        final controller = _controller(api);
        await controller.ensureEmojiCatalog(site);

        expect(
          controller.searchEmojis(site, 'match', limit: 500),
          hasLength(50),
        );
      });

      test(
        'aliases load independently and follow web search ranking',
        () async {
          final api = _PresentationApi()
            ..emojis = const [
              SiteEmoji(name: 'glove', url: 'glove.png'),
              SiteEmoji(name: 'heart', url: 'heart.png'),
              SiteEmoji(name: 'love_letter', url: 'love-letter.png'),
            ];
          final aliasGate = Completer<Map<String, List<String>>>();
          api.emojiAliasGate = aliasGate;
          final controller = _controller(api);

          await controller.ensureEmojiCatalog(site);
          final first = controller.ensureEmojiSearchAliases(site);
          final second = controller.ensureEmojiSearchAliases(site);
          expect(second, same(first));
          aliasGate.complete({
            'heart': ['love'],
            'missing': ['love'],
          });
          await Future.wait([first, second]);

          expect(api.emojiCalls, 1);
          expect(api.emojiAliasCalls, 1);
          expect(controller.searchEmojis(site, 'love', limit: 50), const [
            SiteEmoji(name: 'love_letter', url: 'love-letter.png'),
            SiteEmoji(name: 'heart', url: 'heart.png'),
            SiteEmoji(name: 'glove', url: 'glove.png'),
          ]);
        },
      );

      test('catalog warming retries a failure but reuses a hit', () async {
        await _installDiagnostics('emoji-catalog-warm');
        final api = _PresentationApi()
          ..emojiError = StateError('catalog unavailable');
        final controller = _controller(api);

        expect(await controller.ensureEmojiCatalog(site), isNull);
        expect(api.emojiCalls, 1);

        expect(await controller.ensureEmojiCatalog(site), isNull);
        expect(api.emojiCalls, 1);

        api
          ..emojiError = null
          ..emojis = const [SiteEmoji(name: 'wave', url: 'wave.png')];

        expect(await controller.warmEmojiCatalog(site), isNotNull);
        expect(api.emojiCalls, 2);
        expect(controller.knowsEmoji(site, 'wave'), isTrue);

        expect(await controller.warmEmojiCatalog(site), isNotNull);
        expect(api.emojiCalls, 2);
      });

      test('explicit refresh recovers failed metadata', () async {
        await _installDiagnostics('emoji-metadata-retry');
        final api = _PresentationApi()
          ..emojiError = StateError('catalog unavailable')
          ..emojiAliasError = StateError('aliases unavailable');
        final controller = _controller(api);

        expect(await controller.ensureEmojiCatalog(site), isNull);
        expect(await controller.ensureEmojiSearchAliases(site), isNull);
        expect(controller.emojiCatalogFor(site), isNull);
        expect(controller.emojiSearchAliasesFor(site), isNull);

        api
          ..emojiError = null
          ..emojiAliasError = null
          ..emojis = const [SiteEmoji(name: 'wave', url: 'wave.png')]
          ..emojiAliases = const {
            'wave': ['hello'],
          };
        expect(await controller.ensureEmojiCatalog(site), isNull);
        expect(await controller.ensureEmojiSearchAliases(site), isNull);
        expect(api.emojiCalls, 1);
        expect(api.emojiAliasCalls, 1);

        expect(await controller.refreshEmojiCatalog(site), isNotNull);
        expect(await controller.refreshEmojiSearchAliases(site), isNotNull);
        expect(controller.searchEmojis(site, 'hello').single.name, 'wave');
      });

      test(
        'site invalidation rejects late catalog and alias responses',
        () async {
          final catalogGate = Completer<List<SiteEmoji>>();
          final aliasGate = Completer<Map<String, List<String>>>();
          final api = _PresentationApi()
            ..emojiGate = catalogGate
            ..emojiAliasGate = aliasGate;
          final lifecycle = SiteLifecycle();
          final controller = _controller(api, lifecycle: lifecycle);

          final catalog = controller.ensureEmojiCatalog(site);
          final aliases = controller.ensureEmojiSearchAliases(site);
          await Future.wait([
            api.emojiRequestStarted.future,
            api.emojiAliasRequestStarted.future,
          ]);
          lifecycle.invalidate(site);
          controller.forget(site);
          catalogGate.complete(const [
            SiteEmoji(name: 'wave', url: 'wave.png'),
          ]);
          aliasGate.complete(const {
            'wave': ['hello'],
          });

          expect(await catalog, isNull);
          expect(await aliases, isNull);
          expect(controller.emojiCatalogFor(site), isNull);
          expect(controller.emojiSearchAliasesFor(site), isNull);
        },
      );
    });

    group('lifecycle races and reset', () {
      test(
        'rejects a late config response after invalidation and forgets synchronously',
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
        },
      );

      test(
        'prevents previous-session config persistence during reentrant invalidation',
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
        },
      );

      test('prevents config persistence during reentrant disposal', () async {
        final api = _PresentationApi()
          ..config = const SiteConfig(emojiSet: 'google');
        var persistenceCalls = 0;
        final controller = _controller(
          api,
          onConfigLoaded: (_, _) async => persistenceCalls++,
          autoDispose: false,
        );
        controller.addListener(controller.dispose);

        await controller.ensureConfig(site);

        expect(persistenceCalls, 0);
      });

      test('forget clears custom artwork and the autocomplete index', () async {
        final api = _PresentationApi()
          ..custom = {'party': '/uploads/party.png'}
          ..emojis = const [SiteEmoji(name: 'party', url: 'party.png')];
        final controller = _controller(api);
        final initialPresentation = controller.presentationTokenFor(site);
        await controller.ensureCustomEmojis(site);
        final customPresentation = controller.presentationTokenFor(site);
        await controller.ensureEmojiCatalog(site);
        expect(customPresentation, isNot(same(initialPresentation)));
        expect(controller.presentationTokenFor(site), same(customPresentation));
        expect(controller.searchEmojis(site, 'party'), isNotEmpty);

        controller.forget(site);

        expect(controller.searchEmojis(site, 'party'), isEmpty);
        expect(
          controller.emojiUrlFor(site, 'party'),
          'https://meta.example/images/emoji/twitter/party.png',
        );
        expect(
          controller.presentationTokenFor(site),
          same(initialPresentation),
        );
      });
    });
  });
}

Future<DiagnosticsController> _installDiagnostics(String sessionId) async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: sessionId,
  );
  final binding = DiagnosticsSink.install(diagnostics);
  addTearDown(() async {
    binding.close();
    await diagnostics.close();
  });
  return diagnostics;
}

Matcher _isAppearanceFailure(String operation) => isA<ErrorDiagnosticEvent>()
    .having((event) => event.operation, 'operation', operation)
    .having((event) => event.source, 'source', 'presentation')
    .having((event) => event.severity, 'severity', DiagnosticSeverity.warning)
    .having((event) => event.handled, 'handled', isTrue)
    .having((event) => event.degraded, 'degraded', isTrue);

SitePresentationController _controller(
  _PresentationApi api, {
  _Credentials? credentials,
  SiteLifecycle? lifecycle,
  Map<String, SiteConfig> persisted = const {},
  Map<String, SiteAppearance> persistedAppearances = const {},
  SiteAppearanceLoaded? onAppearanceLoaded,
  SiteConfigLoaded? onConfigLoaded,
  Duration persistedFreshness =
      SitePresentationController.defaultPersistedFreshness,
  DateTime Function()? clock,
  bool autoDispose = true,
}) {
  final controller = SitePresentationController(
    loadAppearance: api.loadAppearance,
    loadConfig: api.loadConfig,
    loadCustomEmojis: api.loadCustomEmojis,
    loadEmojiCatalog: api.loadEmojiCatalog,
    loadEmojiSearchAliases: api.loadEmojiSearchAliases,
    credentials: credentials ?? _Credentials(),
    lifecycle: lifecycle ?? SiteLifecycle(),
    readPersistedAppearance: (siteUrl) => persistedAppearances[siteUrl],
    readPersistedConfig: (siteUrl) => persisted[siteUrl],
    onAppearanceLoaded: onAppearanceLoaded ?? (_, _) async {},
    onConfigLoaded: onConfigLoaded ?? (_, _) async {},
    persistedFreshness: persistedFreshness,
    clock: clock,
  );
  if (autoDispose) addTearDown(controller.dispose);
  return controller;
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
  Object? emojiError;
  Completer<List<SiteEmoji>>? emojiGate;
  Completer<void> emojiRequestStarted = Completer<void>();
  int emojiCalls = 0;
  Map<String, List<String>> emojiAliases = const {};
  Object? emojiAliasError;
  Completer<Map<String, List<String>>>? emojiAliasGate;
  Completer<void> emojiAliasRequestStarted = Completer<void>();
  int emojiAliasCalls = 0;

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

  Future<SiteEmojiCatalog> loadEmojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    emojiCalls++;
    if (!emojiRequestStarted.isCompleted) emojiRequestStarted.complete();
    if (emojiError case final error?) throw error;
    final flat = await (emojiGate?.future ?? Future.value(emojis));
    return SiteEmojiCatalog(
      groups: [SiteEmojiGroup(id: 'default', emojis: flat)],
    );
  }

  Future<Map<String, List<String>>> loadEmojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    emojiAliasCalls++;
    if (!emojiAliasRequestStarted.isCompleted) {
      emojiAliasRequestStarted.complete();
    }
    if (emojiAliasError case final error?) throw error;
    return emojiAliasGate?.future ?? emojiAliases;
  }
}
