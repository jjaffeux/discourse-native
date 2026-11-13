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

  final Map<String, _PresentationSession> _sessions = {};
  late final _appearances = _PresentationResource<SiteAppearance>(
    this,
    (session) => session.appearance,
  );
  late final _configs = _PresentationResource<SiteConfig>(
    this,
    (session) => session.config,
  );
  late final _customEmojis = _PresentationResource<Map<String, String>>(
    this,
    (session) => session.custom,
  );
  late final _emojiCatalogs = _PresentationResource<SiteEmojiCatalog>(
    this,
    (session) => session.catalog,
    suppressFailedReads: true,
  );
  late final _emojiSearchAliases =
      _PresentationResource<Map<String, List<String>>>(
        this,
        (session) => session.aliases,
        suppressFailedReads: true,
      );

  _PresentationSession? _existingSession(String siteUrl) {
    final session = _sessions[siteUrl];
    if (session == null || session.isCurrent) return session;
    _retireSession(session);
    return _sessions[siteUrl];
  }

  _PresentationSession _sessionFor(String siteUrl) {
    final held = _existingSession(siteUrl);
    if (held != null) return held;
    final session = _PresentationSession(
      this,
      siteUrl,
      lifecycle.capture(siteUrl),
    );
    _sessions[siteUrl] = session;
    session.observeRetirement();
    return session;
  }

  void _retireSession(_PresentationSession session) {
    if (!identical(_sessions[session.siteUrl], session)) {
      session.retire();
      return;
    }
    final siteUrl = session.siteUrl;
    final appearanceChanged =
        session.appearance.value != null &&
        session.appearance.value != readPersistedAppearance(siteUrl);
    final configChanged = session.config.value != null;
    final customChanged = session.custom.value?.isNotEmpty == true;
    _invalidatedPersistedAppearances.add(siteUrl);
    _invalidatedPersistedConfigs.add(siteUrl);
    session.retire();
    _presentationTokens.remove(siteUrl);
    _notifyEmojiChanged(siteUrl);
    if (appearanceChanged || configChanged || customChanged) notifySafely();
  }

  static final Object _unchangedPresentation = Object();
  final Map<String, Object> _presentationTokens = {};

  final Map<String, FrameSafeValueNotifier<int>> _emojiChanges = {};
  final Map<String, Map<String, String>> _shortcodeAliases = {};

  /// Catalog and alias changes only rebuild consumers of emoji presentation.
  Listenable emojiChangesFor(String siteUrl) => _emojiChangesFor(siteUrl);

  FrameSafeValueNotifier<int> _emojiChangesFor(String siteUrl) =>
      _emojiChanges.putIfAbsent(siteUrl, () => FrameSafeValueNotifier(0));

  void _notifyEmojiChanged(String siteUrl) {
    _shortcodeAliases.remove(siteUrl);
    final changes = _emojiChanges[siteUrl];
    if (changes != null) changes.value++;
  }

  @override
  void dispose() {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      session.retire();
    }
    for (final changes in _emojiChanges.values) {
      changes.dispose();
    }
    super.dispose();
  }

  bool get _isDisposed => isDisposed;

  Object presentationTokenFor(String siteUrl) =>
      _presentationTokens[siteUrl] ?? _unchangedPresentation;

  SiteAppearance? appearanceFor(String siteUrl) =>
      _appearances[siteUrl] ?? readPersistedAppearance(siteUrl);

  SiteConfig? accountConfigFor(String siteUrl) {
    if (isDisposed) return null;
    _sessionFor(siteUrl);
    return _configs[siteUrl] ??
        (_invalidatedPersistedConfigs.contains(siteUrl)
            ? null
            : readPersistedConfig(siteUrl));
  }

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
    final normalized = base.toLowerCase();
    if (catalog.byName.containsKey(base)) return name;
    if (catalog.byName.containsKey(normalized)) {
      return '$normalized${tone?.group(0) ?? ''}';
    }

    final canonical =
        _shortcodeAliases.putIfAbsent(siteUrl, () {
          final resolved = <String, String>{};
          final aliases = _emojiSearchAliases[siteUrl] ?? const {};
          // Preserve canonical names; site data uses both canonical -> aliases and
          // alias -> canonical names. Build this index once per metadata change.
          for (final entry in aliases.entries) {
            if (!catalog.byName.containsKey(entry.key)) continue;
            for (final alias in entry.value) {
              resolved.putIfAbsent(alias.toLowerCase(), () => entry.key);
            }
          }
          for (final entry in aliases.entries) {
            final canonical = entry.value
                .where(catalog.byName.containsKey)
                .firstOrNull;
            if (canonical != null) {
              resolved.putIfAbsent(entry.key.toLowerCase(), () => canonical);
            }
          }
          return resolved;
        })[normalized] ??
        discourseEmojiAliases[normalized];
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
    hasChanged: (catalog) => catalog != _emojiCatalogs[siteUrl],
    onChanged: () => _notifyEmojiChanged(siteUrl),
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
    hasChanged: (aliases) {
      final previous = _emojiSearchAliases[siteUrl];
      return previous == null ||
          previous.length != aliases.length ||
          aliases.entries.any(
            (entry) => !listEquals(previous[entry.key], entry.value),
          );
    },
    onChanged: () => _notifyEmojiChanged(siteUrl),
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
    final prefixes = <SiteEmoji>[];
    final aliasMatches = <SiteEmoji>[];
    final infixes = <SiteEmoji>[];
    final aliases = _emojiSearchAliases[siteUrl] ?? const {};
    for (final emoji in catalog.alphabetical) {
      final nameMatch = emoji.name.toLowerCase().indexOf(needle);
      if (nameMatch == 0) {
        prefixes.add(emoji);
        if (prefixes.length == cappedLimit) return prefixes;
      } else if (aliasMatches.length < cappedLimit) {
        final matchesAlias =
            aliases[emoji.name]?.any(
              (alias) => alias.toLowerCase().startsWith(needle),
            ) ??
            false;
        if (matchesAlias) {
          aliasMatches.add(emoji);
        } else if (infixes.length < cappedLimit && nameMatch > 0) {
          infixes.add(emoji);
        }
      }
    }
    prefixes.addAll(aliasMatches.take(cappedLimit - prefixes.length));
    prefixes.addAll(infixes.take(cappedLimit - prefixes.length));
    return prefixes;
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
    _invalidatedPersistedAppearances.add(siteUrl);
    _invalidatedPersistedConfigs.add(siteUrl);
    final session = _sessions[siteUrl];
    if (session != null) {
      _retireSession(session);
    } else {
      // Without a session every answer came from the persisted snapshot, and
      // forgetting a forum is how that snapshot leaves.
      _notifyEmojiChanged(siteUrl);
    }
  }

  /// Reports that the persisted snapshot [configFor] falls back to was
  /// replaced. The rail owns that snapshot, so nothing here can see the change;
  /// a fetched config hides it, and then no emoji answer moved.
  void persistedConfigChanged(String siteUrl) {
    if (!isDisposed && _configs[siteUrl] == null) _notifyEmojiChanged(siteUrl);
  }

  void _notifyPresentationChanged(String siteUrl) {
    _presentationTokens[siteUrl] = Object();
    _notifyEmojiChanged(siteUrl);
    notifySafely();
  }

  Future<T?> _withCredentials<T>(
    String siteUrl,
    _PresentationSession session,
    Future<T> Function(String? apiKey, String? clientId) load,
  ) async {
    final auth = await AccountRequestSession(
      siteUrl,
      session.lease,
    ).credentials(credentials);
    if (!session.isCurrent) return null;
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
  _PresentationResource(
    this.owner,
    this.entryFor, {
    this.suppressFailedReads = false,
  });

  final SitePresentationController owner;
  final bool suppressFailedReads;
  final _ResourceEntry<T> Function(_PresentationSession) entryFor;

  T? operator [](String siteUrl) {
    final session = owner._existingSession(siteUrl);
    return session == null ? null : entryFor(session).value;
  }

  Future<T?> request(
    String siteUrl, {
    required Future<T?> Function(String? apiKey, String? clientId) load,
    bool refresh = false,
    bool Function()? isWarm,
    bool Function(T value)? hasChanged,
    VoidCallback? onChanged,
    Future<void> Function(T value)? persist,
    bool persistOnlyChanges = false,
  }) {
    if (owner._isDisposed) return Future.value(null);
    final session = owner._sessionFor(siteUrl);
    final entry = entryFor(session);
    if (suppressFailedReads && !refresh && entry.value != null) {
      return Future.value(entry.value);
    }
    final active = entry.request;
    if (active != null) return active.join();
    if (suppressFailedReads && !refresh && entry.failed) {
      return Future.value(null);
    }
    if (refresh) entry.failed = false;

    final request = RequestIntentOperation<T?>();
    entry.request = request;
    request.start(() async {
      if (!session.isCurrent || (!refresh && (isWarm?.call() ?? false))) {
        return null;
      }
      if (entry.loading || (!refresh && entry.value != null)) {
        return entry.value;
      }
      if (refresh) entry.attempts = 0;
      if (entry.attempts >= owner.maxAttempts) return entry.value;
      entry.attempts++;
      entry.loading = true;
      final lease = session.lease;
      try {
        final value = await owner._withCredentials(siteUrl, session, load);
        if (value == null || !session.isCurrent) return null;
        var changed = false;
        final accepted = lease.commit(() {
          changed = hasChanged?.call(value) ?? false;
          entry.value = value;
          entry.failed = false;
          if (changed) {
            if (onChanged != null) {
              onChanged();
            } else {
              owner._notifyPresentationChanged(siteUrl);
            }
          }
        });
        if (!accepted || !session.isCurrent) return null;
        if (persist != null && (!persistOnlyChanges || changed)) {
          try {
            await persist(value);
          } catch (_) {
            if (!session.isCurrent) return null;
          }
        }
        return value;
      } catch (_) {
        if (!session.isCurrent) return null;
        entry.failed = true;
        return null;
      } finally {
        entry.loading = false;
      }
    });
    request.future.whenComplete(() {
      if (identical(entry.request, request)) entry.request = null;
    }).ignore();
    return request.future;
  }

  void forgiveAttempts(String siteUrl) {
    final session = owner._existingSession(siteUrl);
    if (session == null) return;
    final entry = entryFor(session);
    if (entry.loading || entry.value != null) return;
    entry.attempts = 0;
  }
}

final class _ResourceEntry<T extends Object> {
  T? value;
  int attempts = 0;
  bool loading = false;
  bool failed = false;
  RequestIntentOperation<T?>? request;

  void clear() {
    request?.future.ignore();
    request = null;
    value = null;
    loading = false;
  }
}

final class _PresentationSession {
  _PresentationSession(this.owner, this.siteUrl, this.lease);

  final SitePresentationController owner;
  final String siteUrl;
  final SiteLease lease;
  final appearance = _ResourceEntry<SiteAppearance>();
  final config = _ResourceEntry<SiteConfig>();
  final custom = _ResourceEntry<Map<String, String>>();
  final catalog = _ResourceEntry<SiteEmojiCatalog>();
  final aliases = _ResourceEntry<Map<String, List<String>>>();
  void Function()? _detach;
  bool _retired = false;

  bool get isCurrent =>
      !_retired && lease.isCurrent && identical(owner._sessions[siteUrl], this);

  void observeRetirement() =>
      _detach = lease.onRetire(() => owner._retireSession(this));

  void retire() {
    if (_retired) return;
    _retired = true;
    _detach?.call();
    _detach = null;
    if (identical(owner._sessions[siteUrl], this)) {
      owner._sessions.remove(siteUrl);
    }
    appearance.clear();
    config.clear();
    custom.clear();
    catalog.clear();
    aliases.clear();
  }
}
