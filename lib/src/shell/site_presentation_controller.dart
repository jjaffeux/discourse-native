import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
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
typedef SiteEmojiLoader =
    Future<List<SiteEmoji>> Function({
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

/// Per-site appearance, settings, and emoji metadata used to decide rendering.
///
/// This state has different freshness and notification needs from navigation:
/// settings and custom artwork can repaint visible content, while the complete
/// emoji index only needs to refresh an open composer's autocomplete.
final class SitePresentationController extends FrameSafeNotifier {
  static const Duration defaultPersistedFreshness = Duration(minutes: 5);

  SitePresentationController({
    required this.loadAppearance,
    required this.loadConfig,
    required this.loadCustomEmojis,
    required this.loadEmojis,
    required this.credentials,
    required this.lifecycle,
    required this.readPersistedAppearance,
    required this.readPersistedConfig,
    required this.onAppearanceLoaded,
    required this.onConfigLoaded,
    required this.onEmojiIndexChanged,
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
  final SiteEmojiLoader loadEmojis;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final PersistedSiteAppearanceReader readPersistedAppearance;
  final PersistedSiteConfigReader readPersistedConfig;
  final SiteAppearanceLoaded onAppearanceLoaded;
  final SiteConfigLoaded onConfigLoaded;
  final VoidCallback onEmojiIndexChanged;
  final int maxAttempts;
  final Duration persistedFreshness;
  final DateTime Function() _clock;
  late final DateTime _persistedFreshUntil;
  final Set<String> _invalidatedPersistedAppearances = {};
  final Set<String> _invalidatedPersistedConfigs = {};

  final _appearances = _RetryingSiteCache<SiteAppearance>();

  void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'presentation',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }

  final _configs = _RetryingSiteCache<SiteConfig>();
  final Map<String, Future<void>> _configRequests = {};
  final _customEmojis = _RetryingSiteCache<Map<String, String>>();
  final _emojis = _RetryingSiteCache<List<SiteEmoji>>();
  static final Object _unchangedPresentation = Object();
  final Map<String, Object> _presentationTokens = {};

  /// Opaque identity for widgets that depend on any visual metadata for a
  /// site. It changes for config and custom artwork, but not for the full
  /// autocomplete-only emoji index.
  Object presentationTokenFor(String siteUrl) =>
      _presentationTokens[siteUrl] ?? _unchangedPresentation;

  SiteAppearance? appearanceFor(String siteUrl) =>
      _appearances[siteUrl] ?? readPersistedAppearance(siteUrl);

  SiteConfig configFor(String siteUrl) =>
      _configs[siteUrl] ??
      readPersistedConfig(siteUrl) ??
      const SiteConfig.unknown();

  Future<void> ensureAppearance(String siteUrl) =>
      _ensureAppearance(siteUrl, refresh: false);

  /// Revalidates persisted or already-fetched colors immediately.
  ///
  /// Ordinary startup goes through [ensureAppearance] and can use the warm
  /// persisted snapshot. An explicit refresh is a new retry boundary and keeps
  /// the last usable colors in place if the request fails.
  Future<void> refreshAppearance(String siteUrl) =>
      _ensureAppearance(siteUrl, refresh: true);

  Future<void> _ensureAppearance(
    String siteUrl, {
    required bool refresh,
  }) async {
    if (isDisposed || (!refresh && _warmPersistedAppearance(siteUrl))) return;
    if (!_appearances.start(siteUrl, maxAttempts, refresh: refresh)) return;
    final lease = lifecycle.capture(siteUrl);

    try {
      final appearance = await _withCredentials(
        siteUrl,
        lease,
        (apiKey, clientId) => loadAppearance(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
        ),
      );
      if (appearance == null || !appearance.isKnown || isDisposed) return;

      var changed = false;
      final accepted = lease.commit(() {
        changed = appearanceFor(siteUrl) != appearance;
        _appearances.complete(siteUrl, appearance);
        if (changed) _notifyPresentationChanged(siteUrl);
      });
      // Publishing can synchronously dispose this owner through a listener.
      // Persistence belongs to the live controller just as much as the fetch,
      // so do not let that reentrant teardown enqueue a stale write.
      if (!accepted || !lease.isCurrent || isDisposed) return;
      if (!changed) return;

      try {
        await onAppearanceLoaded(siteUrl, appearance);
      } catch (error, stackTrace) {
        if (isDisposed || !lease.isCurrent) return;
        _report(error, stackTrace, 'siteAppearance.persist');
        // The in-memory palette is still useful. A later rail write can retry
        // persisting it with the rest of the instance snapshot.
      }
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _report(error, stackTrace, 'siteAppearance.load');
      // Appearance is optional; persisted or native colors remain in place.
    } finally {
      if (!isDisposed) lease.commit(() => _appearances.finish(siteUrl));
    }
  }

  String emojiUrlFor(String siteUrl, String name) {
    final custom = _customEmojis[siteUrl]?[name];
    if (custom != null) return _resolveUrl(siteUrl, custom);
    return configFor(siteUrl).emojiUrl(name, siteUrl: siteUrl);
  }

  Future<void> ensureConfig(String siteUrl) =>
      _configRequest(siteUrl, refresh: false);

  /// Resolves a settings payload the server actually answered with.
  ///
  /// Unlike [configFor], this returns null when the optional settings request
  /// failed and only defaults are available. Callers which use a client
  /// setting to avoid probing an optional server route need that distinction.
  Future<SiteConfig?> resolveConfig(String siteUrl) async {
    await ensureConfig(siteUrl);
    if (isDisposed) return null;
    final fetched = _configs[siteUrl];
    if (fetched != null) return fetched;
    return _warmPersistedConfig(siteUrl) ? readPersistedConfig(siteUrl) : null;
  }

  /// Revalidates persisted or already-fetched client settings immediately.
  ///
  /// This bypasses the short warm-start window and resets the bounded cache's
  /// retry budget for a user-initiated refresh without discarding the value the
  /// UI is currently using.
  Future<void> refreshConfig(String siteUrl) =>
      _configRequest(siteUrl, refresh: true);

  Future<void> _configRequest(String siteUrl, {required bool refresh}) {
    final active = _configRequests[siteUrl];
    if (active != null) return active;

    late final Future<void> request;
    request = _ensureConfig(siteUrl, refresh: refresh).whenComplete(() {
      if (identical(_configRequests[siteUrl], request)) {
        final removed = _configRequests.remove(siteUrl);
        assert(identical(removed, request));
      }
    });
    _configRequests[siteUrl] = request;
    return request;
  }

  Future<void> _ensureConfig(String siteUrl, {required bool refresh}) async {
    if (isDisposed || (!refresh && _warmPersistedConfig(siteUrl))) return;
    if (!_configs.start(siteUrl, maxAttempts, refresh: refresh)) return;
    final lease = lifecycle.capture(siteUrl);

    try {
      final config = await _withCredentials(
        siteUrl,
        lease,
        (apiKey, clientId) =>
            loadConfig(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId),
      );
      if (config == null || isDisposed) return;

      final accepted = lease.commit(() {
        final changed = configFor(siteUrl) != config;
        _configs.complete(siteUrl, config);
        if (changed) _notifyPresentationChanged(siteUrl);
      });
      // A notification listener can synchronously rotate the site's session.
      if (!accepted || !lease.isCurrent || isDisposed) return;

      try {
        await onConfigLoaded(siteUrl, config);
      } catch (error, stackTrace) {
        if (isDisposed || !lease.isCurrent) return;
        _report(error, stackTrace, 'siteConfig.persist');
        // The fetched value remains useful for this session. Persistence can
        // be retried when some later instance-store change writes the rail.
      }
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _report(error, stackTrace, 'siteConfig.load');
      // Every field has a safe default, so a failed optional request is quiet.
    } finally {
      if (!isDisposed) lease.commit(() => _configs.finish(siteUrl));
    }
  }

  Future<void> ensureCustomEmojis(String siteUrl) async {
    if (isDisposed || !_customEmojis.start(siteUrl, maxAttempts)) return;
    final lease = lifecycle.capture(siteUrl);

    try {
      final emojis = await _withCredentials(
        siteUrl,
        lease,
        (apiKey, clientId) => loadCustomEmojis(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
        ),
      );
      if (emojis == null || isDisposed) return;

      lease.commit(() {
        final changed = !mapEquals(_customEmojis[siteUrl], emojis);
        _customEmojis.complete(siteUrl, Map.unmodifiable(emojis));
        if (changed && emojis.isNotEmpty) {
          _notifyPresentationChanged(siteUrl);
        }
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _report(error, stackTrace, 'emoji.loadCustom');
      // Core and set emoji still have deterministic URLs without this map.
    } finally {
      if (!isDisposed) lease.commit(() => _customEmojis.finish(siteUrl));
    }
  }

  Future<void> ensureEmojis(String siteUrl) async {
    if (isDisposed || !_emojis.start(siteUrl, maxAttempts)) return;
    final lease = lifecycle.capture(siteUrl);

    try {
      final emojis = await _withCredentials(
        siteUrl,
        lease,
        (apiKey, clientId) =>
            loadEmojis(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId),
      );
      if (emojis == null || isDisposed) return;

      lease.commit(() {
        _emojis.complete(siteUrl, List.unmodifiable(emojis));
        onEmojiIndexChanged();
      });
    } catch (error, stackTrace) {
      if (isDisposed || !lease.isCurrent) return;
      _report(error, stackTrace, 'emoji.loadIndex');
      // Shortcodes remain valid text when autocomplete metadata is absent.
    } finally {
      if (!isDisposed) lease.commit(() => _emojis.finish(siteUrl));
    }
  }

  List<SiteEmoji> searchEmojis(String siteUrl, String query, {int limit = 7}) {
    if (limit <= 0) return const [];
    final all = _emojis[siteUrl];
    if (all == null) return const [];

    final needle = query.toLowerCase();
    final best = <(int, SiteEmoji)>[];
    for (final emoji in all) {
      final rank = emoji.rank(needle);
      if (rank == null) continue;

      final candidate = (rank, emoji);
      var index = 0;
      while (index < best.length &&
          _compareEmoji(best[index], candidate) <= 0) {
        index++;
      }
      if (index >= limit) continue;

      best.insert(index, candidate);
      if (best.length > limit) best.removeLast();
    }
    return [for (final match in best) match.$2];
  }

  static int _compareEmoji((int, SiteEmoji) a, (int, SiteEmoji) b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    final length = a.$2.name.length.compareTo(b.$2.name.length);
    return length != 0 ? length : a.$2.name.compareTo(b.$2.name);
  }

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

  /// Drops one site's fetched state immediately; the shell owns invalidation.
  void forget(String siteUrl) {
    if (isDisposed) return;
    // Forget marks an identity/lifecycle boundary in the shell. A value still
    // present on the immutable instance may belong to the account that was
    // just disconnected, so it must not regain warm-start status.
    _invalidatedPersistedAppearances.add(siteUrl);
    _invalidatedPersistedConfigs.add(siteUrl);
    final configRequest = _configRequests.remove(siteUrl);
    configRequest?.ignore();
    final oldAppearance = appearanceFor(siteUrl);
    final oldConfig = configFor(siteUrl);
    final customChanged = _customEmojis[siteUrl]?.isNotEmpty ?? false;
    final emojiIndexChanged = _emojis.contains(siteUrl);

    _appearances.forget(siteUrl);
    _configs.forget(siteUrl);
    _customEmojis.forget(siteUrl);
    _emojis.forget(siteUrl);
    _presentationTokens.remove(siteUrl);

    if (oldAppearance != appearanceFor(siteUrl) ||
        oldConfig != configFor(siteUrl) ||
        customChanged) {
      notifySafely();
    }
    if (emojiIndexChanged) onEmojiIndexChanged();
  }

  void _notifyPresentationChanged(String siteUrl) {
    _presentationTokens[siteUrl] = Object();
    notifySafely();
  }

  Future<T?> _withCredentials<T>(
    String siteUrl,
    SiteLease lease,
    Future<T> Function(String? apiKey, String clientId) load,
  ) async {
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (isDisposed || !lease.isCurrent) return null;
    final clientId = await credentials.clientId();
    if (isDisposed || !lease.isCurrent) return null;
    return load(apiKey, clientId);
  }

  static String _resolveUrl(String siteUrl, String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.hasScheme) return value;
    return Uri.parse('$siteUrl/').resolve(value).toString();
  }
}

final class _RetryingSiteCache<T> {
  final Map<String, T> _values = {};
  final Map<String, int> _attempts = {};
  final Set<String> _loading = {};

  T? operator [](String siteUrl) => _values[siteUrl];

  bool contains(String siteUrl) => _values.containsKey(siteUrl);

  bool start(String siteUrl, int maxAttempts, {bool refresh = false}) {
    if (_loading.contains(siteUrl)) return false;
    if (!refresh && _values.containsKey(siteUrl)) return false;
    if (refresh) _attempts.remove(siteUrl);
    final attempts = _attempts[siteUrl] ?? 0;
    if (attempts >= maxAttempts) return false;
    _attempts[siteUrl] = attempts + 1;
    _loading.add(siteUrl);
    return true;
  }

  void complete(String siteUrl, T value) {
    _values[siteUrl] = value;
  }

  void finish(String siteUrl) {
    _loading.remove(siteUrl);
  }

  void forget(String siteUrl) {
    _values.remove(siteUrl);
    _attempts.remove(siteUrl);
    _loading.remove(siteUrl);
  }
}
