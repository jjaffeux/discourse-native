import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/request_intent.dart';
import '../data/site_lifecycle.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_emoji_aliases.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';

typedef SiteAppearanceLoader =
    Future<SiteAppearance?> Function({
      required String siteUrl,
      String? apiKey,
      String? clientId,
    });

typedef SiteConfigLoader =
    Future<SiteConfig> Function({
      required String siteUrl,
      String? apiKey,
      String? clientId,
    });
typedef CustomEmojiLoader =
    Future<Map<String, String>> Function({
      required String siteUrl,
      String? apiKey,
      String? clientId,
    });
typedef SiteEmojiCatalogLoader =
    Future<SiteEmojiCatalog> Function({
      required String siteUrl,
      String? apiKey,
      String? clientId,
    });
typedef EmojiSearchAliasesLoader =
    Future<Map<String, List<String>>> Function({
      required String siteUrl,
      String? apiKey,
      String? clientId,
    });
typedef PersistedSiteConfigReader = SiteConfig? Function(String siteUrl);
typedef SiteConfigLoaded =
    Future<void> Function(String siteUrl, SiteConfig config);
typedef PersistedSiteAppearanceReader =
    SiteAppearance? Function(String siteUrl);
typedef SiteAppearanceLoaded =
    Future<void> Function(String siteUrl, SiteAppearance appearance);

final class SitePresentationController extends FrameSafeNotifier {
  static const Duration defaultPersistedFreshness = Duration(minutes: 5);

  SitePresentationController({
    required this.loadAppearance,
    required this.loadConfig,
    required this.loadCustomEmojis,
    required this.loadEmojiCatalog,
    required this.loadEmojiSearchAliases,
    required this.credentials,
    required this.lifecycle,
    required this.readPersistedAppearance,
    required this.readPersistedConfig,
    required this.onAppearanceLoaded,
    required this.onConfigLoaded,
    this.maxAttempts = 3,
    this.persistedFreshness = defaultPersistedFreshness,
    DateTime Function()? clock,
  }) : assert(maxAttempts > 0),
       assert(persistedFreshness >= Duration.zero),
       _clock = clock ?? DateTime.now {
    _persistedFreshUntil = _clock().add(persistedFreshness);
  }

  final SiteAppearanceLoader loadAppearance;
  final SiteConfigLoader loadConfig;
  final CustomEmojiLoader loadCustomEmojis;
  final SiteEmojiCatalogLoader loadEmojiCatalog;
  final EmojiSearchAliasesLoader loadEmojiSearchAliases;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final PersistedSiteAppearanceReader readPersistedAppearance;
  final PersistedSiteConfigReader readPersistedConfig;
  final SiteAppearanceLoaded onAppearanceLoaded;
  final SiteConfigLoaded onConfigLoaded;
  final int maxAttempts;
  final Duration persistedFreshness;
  final DateTime Function() _clock;
  late final DateTime _persistedFreshUntil;
  final Set<String> _invalidatedPersistedAppearances = {};
  final Set<String> _invalidatedPersistedConfigs = {};

  late final _appearances = _PresentationResource<SiteAppearance>(this);

  late final _configs = _PresentationResource<SiteConfig>(this);
  late final _customEmojis = _PresentationResource<Map<String, String>>(this);
  late final _emojiCatalogs = _PresentationResource<SiteEmojiCatalog>(
    this,
    suppressFailedReads: true,
  );
  late final _emojiSearchAliases =
      _PresentationResource<Map<String, List<String>>>(
        this,
        suppressFailedReads: true,
      );
  static final Object _unchangedPresentation = Object();
  final Map<String, Object> _presentationTokens = {};

  bool get _isDisposed => isDisposed;

  Object presentationTokenFor(String siteUrl) =>
      _presentationTokens[siteUrl] ?? _unchangedPresentation;

  SiteAppearance? appearanceFor(String siteUrl) =>
      _appearances[siteUrl] ?? readPersistedAppearance(siteUrl);

  SiteConfig configFor(String siteUrl) =>
      _configs[siteUrl] ??
      readPersistedConfig(siteUrl) ??
      const SiteConfig.unknown();

  Map<String, String> cachedCustomEmojiFor(String siteUrl) =>
      _customEmojis[siteUrl] ?? const {};

  bool cookingSettingsAreStale(String siteUrl) => _configs[siteUrl] == null;

  Future<void> ensureAppearance(String siteUrl) =>
      _appearanceRequest(siteUrl, refresh: false);

  Future<void> refreshAppearance(String siteUrl) =>
      _appearanceRequest(siteUrl, refresh: true);

  Future<void> _appearanceRequest(String siteUrl, {required bool refresh}) =>
      _appearances.request(
        siteUrl,
        refresh: refresh,
        isWarm: () => _warmPersistedAppearance(siteUrl),
        load: (apiKey, clientId) async {
          final appearance = await loadAppearance(
            siteUrl: siteUrl,
            apiKey: apiKey,
            clientId: clientId,
          );
          return appearance?.isKnown == true ? appearance : null;
        },
        hasChanged: (appearance) => appearanceFor(siteUrl) != appearance,
        persist: (appearance) => onAppearanceLoaded(siteUrl, appearance),
        persistOnlyChanges: true,
      );

  String emojiUrlFor(String siteUrl, String name) {
    final custom = _customEmojis[siteUrl]?[name];
    if (custom != null) return _resolveUrl(siteUrl, custom);
    return configFor(siteUrl).emojiUrl(name, siteUrl: siteUrl);
  }

  String? emojiNameFor(String siteUrl, String name) {
    final tone = _toneSuffix.firstMatch(name);
    final base = tone == null ? name : name.substring(0, tone.start);
    if (_customEmojis[siteUrl]?.containsKey(base) ?? false) return name;

    final catalog = _emojiCatalogs[siteUrl];
    if (catalog == null) return null;
    if (catalog.byName.containsKey(base)) return name;

    final canonical = discourseEmojiAliases[base];
    if (canonical == null || !catalog.byName.containsKey(canonical)) {
      return null;
    }
    return '$canonical${tone?.group(0) ?? ''}';
  }

  bool knowsEmoji(String siteUrl, String name) =>
      emojiNameFor(siteUrl, name) != null;

  static final RegExp _toneSuffix = RegExp(r':t[1-6]$');

  Future<void> ensureConfig(String siteUrl) =>
      _configRequest(siteUrl, refresh: false);

  Future<void> warmConfig(String siteUrl) {
    _configs.forgiveAttempts(siteUrl);
    return RequestIntent.background().run(() => ensureConfig(siteUrl));
  }

  Future<SiteConfig?> resolveConfig(String siteUrl) async {
    await ensureConfig(siteUrl);
    if (isDisposed) return null;
    final fetched = _configs[siteUrl];
    if (fetched != null) return fetched;
    return _warmPersistedConfig(siteUrl) ? readPersistedConfig(siteUrl) : null;
  }

  Future<void> refreshConfig(String siteUrl) =>
      _configRequest(siteUrl, refresh: true);

  Future<void> _configRequest(String siteUrl, {required bool refresh}) =>
      _configs.request(
        siteUrl,
        refresh: refresh,
        isWarm: () => _warmPersistedConfig(siteUrl),
        load: (apiKey, clientId) =>
            loadConfig(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId),
        hasChanged: (config) => configFor(siteUrl) != config,
        persist: (config) => onConfigLoaded(siteUrl, config),
      );

  Future<void> ensureCustomEmojis(String siteUrl) => _customEmojis.request(
    siteUrl,
    load: (apiKey, clientId) async => Map.unmodifiable(
      await loadCustomEmojis(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      ),
    ),
    hasChanged: (emojis) =>
        !mapEquals(_customEmojis[siteUrl], emojis) && emojis.isNotEmpty,
  );

  Future<void> warmCustomEmojis(String siteUrl) {
    _customEmojis.forgiveAttempts(siteUrl);
    return RequestIntent.background().run(() => ensureCustomEmojis(siteUrl));
  }

  SiteEmojiCatalog? emojiCatalogFor(String siteUrl) => _emojiCatalogs[siteUrl];

  Map<String, List<String>>? emojiSearchAliasesFor(String siteUrl) =>
      _emojiSearchAliases[siteUrl];

  Future<SiteEmojiCatalog?> ensureEmojiCatalog(String siteUrl) =>
      _emojiCatalogRequest(siteUrl, refresh: false);

  Future<SiteEmojiCatalog?> warmEmojiCatalog(String siteUrl) {
    final held = _emojiCatalogs[siteUrl];
    if (held != null) return Future.value(held);
    return RequestIntent.background().run(() => refreshEmojiCatalog(siteUrl));
  }

  Future<SiteEmojiCatalog?> refreshEmojiCatalog(String siteUrl) =>
      _emojiCatalogRequest(siteUrl, refresh: true);

  Future<SiteEmojiCatalog?> _emojiCatalogRequest(
    String siteUrl, {
    required bool refresh,
  }) => _emojiCatalogs.request(
    siteUrl,
    refresh: refresh,
    load: (apiKey, clientId) =>
        loadEmojiCatalog(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId),
  );

  Future<Map<String, List<String>>?> ensureEmojiSearchAliases(String siteUrl) =>
      _emojiAliasesRequest(siteUrl, refresh: false);

  Future<Map<String, List<String>>?> refreshEmojiSearchAliases(
    String siteUrl,
  ) => _emojiAliasesRequest(siteUrl, refresh: true);

  Future<Map<String, List<String>>?> _emojiAliasesRequest(
    String siteUrl, {
    required bool refresh,
  }) => _emojiSearchAliases.request(
    siteUrl,
    refresh: refresh,
    load: (apiKey, clientId) async => _immutableAliases(
      await loadEmojiSearchAliases(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
      ),
    ),
  );

  List<SiteEmoji> searchEmojis(String siteUrl, String query, {int limit = 7}) {
    if (limit <= 0) return const [];
    final cappedLimit = limit > 50 ? 50 : limit;
    final catalog = _emojiCatalogs[siteUrl];
    if (catalog == null) return const [];

    final needle = query.toLowerCase();
    // Ranked insertion below decides the whole result from (rank, name), and
    // names are unique in the catalog, so the answer does not depend on the
    // order the catalog is walked in. Sorting a copy of every emoji the site
    // has first only spent a keystroke's budget arriving back where it was.
    final best = <(int, SiteEmoji)>[];
    final aliases = _emojiSearchAliases[siteUrl] ?? const {};
    for (final emoji in catalog.byName.values) {
      final name = emoji.name.toLowerCase();
      final rank = name.startsWith(needle)
          ? 0
          : (aliases[emoji.name]?.any(
                  (alias) => alias.toLowerCase().startsWith(needle),
                ) ??
                false)
          ? 1
          : name.indexOf(needle) > 0
          ? 2
          : null;
      if (rank == null) continue;

      final candidate = (rank, emoji);
      var index = 0;
      while (index < best.length &&
          _compareEmoji(best[index], candidate) <= 0) {
        index++;
      }
      if (index >= cappedLimit) continue;

      best.insert(index, candidate);
      if (best.length > cappedLimit) best.removeLast();
    }
    return [for (final match in best) match.$2];
  }

  static int _compareEmoji((int, SiteEmoji) a, (int, SiteEmoji) b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    return a.$2.name.compareTo(b.$2.name);
  }

  static Map<String, List<String>> _immutableAliases(
    Map<String, List<String>> aliases,
  ) => Map<String, List<String>>.unmodifiable({
    for (final entry in aliases.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  });

  bool get _persistedIsFresh =>
      persistedFreshness > Duration.zero &&
      _clock().isBefore(_persistedFreshUntil);

  bool _warmPersistedAppearance(String siteUrl) {
    if (!_persistedIsFresh ||
        _invalidatedPersistedAppearances.contains(siteUrl)) {
      return false;
    }
    return readPersistedAppearance(siteUrl)?.isKnown == true;
  }

  bool _warmPersistedConfig(String siteUrl) {
    if (!_persistedIsFresh || _invalidatedPersistedConfigs.contains(siteUrl)) {
      return false;
    }
    final config = readPersistedConfig(siteUrl);
    // The persisted model predates freshness metadata. Its unknown sentinel is
    // value-equal to a real site using every core default, so it cannot safely
    // prove that settings were fetched. Err toward one request for that
    // ambiguous case; non-default snapshots are known to have come from the
    // endpoint and are safe to use through the short startup window.
    return config != null && config != const SiteConfig.unknown();
  }

  void forget(String siteUrl) {
    if (isDisposed) return;
    // Forget marks an identity/lifecycle boundary in the shell. A value still
    // present on the immutable instance may belong to the account that was
    // just disconnected, so it must not regain warm-start status.
    _invalidatedPersistedAppearances.add(siteUrl);
    _invalidatedPersistedConfigs.add(siteUrl);
    final oldAppearance = appearanceFor(siteUrl);
    final oldConfig = configFor(siteUrl);
    final customChanged = _customEmojis[siteUrl]?.isNotEmpty ?? false;

    _appearances.forget(siteUrl);
    _configs.forget(siteUrl);
    _customEmojis.forget(siteUrl);
    _emojiCatalogs.forget(siteUrl);
    _emojiSearchAliases.forget(siteUrl);
    _presentationTokens.remove(siteUrl);

    if (oldAppearance != appearanceFor(siteUrl) ||
        oldConfig != configFor(siteUrl) ||
        customChanged) {
      notifySafely();
    }
  }

  void _notifyPresentationChanged(String siteUrl) {
    _presentationTokens[siteUrl] = Object();
    notifySafely();
  }

  Future<T?> _withCredentials<T>(
    String siteUrl,
    SiteLease lease,
    Future<T> Function(String? apiKey, String? clientId) load,
  ) async {
    final auth = await AccountRequestSession(
      siteUrl,
      lease,
    ).credentials(credentials);
    if (isDisposed || !lease.isCurrent) return null;
    return auth.run(
      () => load(auth.apiKey, auth.apiKey == null ? null : auth.clientId),
    );
  }

  static String _resolveUrl(String siteUrl, String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.hasScheme) return value;
    return Uri.parse('$siteUrl/').resolve(value).toString();
  }
}

final class _PresentationResource<T extends Object> {
  _PresentationResource(this.owner, {this.suppressFailedReads = false});

  final SitePresentationController owner;
  final bool suppressFailedReads;
  final Map<String, _ResourceEntry<T>> _entries = {};

  T? operator [](String siteUrl) => _entries[siteUrl]?.value;

  Future<T?> request(
    String siteUrl, {
    required Future<T?> Function(String? apiKey, String? clientId) load,
    bool refresh = false,
    bool Function()? isWarm,
    bool Function(T value)? hasChanged,
    Future<void> Function(T value)? persist,
    bool persistOnlyChanges = false,
  }) {
    if (suppressFailedReads && owner._isDisposed) return Future.value(null);
    final entry = _entries.putIfAbsent(siteUrl, _ResourceEntry<T>.new);
    if (suppressFailedReads && !refresh && entry.value != null) {
      return Future.value(entry.value);
    }
    final active = entry.request;
    if (active != null) return active.join();
    if (suppressFailedReads && !refresh && entry.failed) {
      return Future.value(null);
    }
    if (refresh) entry.failed = false;

    final request = RequestIntentOperation<T?>(() async {
      if (owner._isDisposed || (!refresh && (isWarm?.call() ?? false))) {
        return null;
      }
      if (entry.loading || (!refresh && entry.value != null)) {
        return entry.value;
      }
      if (refresh) entry.attempts = 0;
      if (entry.attempts >= owner.maxAttempts) return entry.value;
      entry.attempts++;
      entry.loading = true;
      final lease = owner.lifecycle.capture(siteUrl);
      try {
        final value = await owner._withCredentials(siteUrl, lease, load);
        if (value == null || owner._isDisposed) return null;
        var changed = false;
        final accepted = lease.commit(() {
          changed = hasChanged?.call(value) ?? false;
          entry.value = value;
          entry.failed = false;
          if (changed) owner._notifyPresentationChanged(siteUrl);
        });
        if (!accepted || !lease.isCurrent || owner._isDisposed) return null;
        if (persist != null && (!persistOnlyChanges || changed)) {
          try {
            await persist(value);
          } catch (_) {
            if (owner._isDisposed || !lease.isCurrent) return null;
          }
        }
        return value;
      } catch (_) {
        if (owner._isDisposed || !lease.isCurrent) return null;
        entry.failed = true;
        return null;
      } finally {
        if (!owner._isDisposed) lease.commit(() => entry.loading = false);
      }
    });
    entry.request = request;
    request.future.whenComplete(() => entry.request = null).ignore();
    return request.future;
  }

  void forgiveAttempts(String siteUrl) {
    final entry = _entries[siteUrl];
    if (entry == null || entry.loading || entry.value != null) return;
    entry.attempts = 0;
  }

  void forget(String siteUrl) {
    _entries.remove(siteUrl)?.request?.future.ignore();
  }
}

final class _ResourceEntry<T extends Object> {
  T? value;
  int attempts = 0;
  bool loading = false;
  bool failed = false;
  RequestIntentOperation<T?>? request;
}
