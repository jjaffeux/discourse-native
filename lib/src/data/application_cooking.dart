import 'dart:async';
import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';

import '../models/site_config.dart';
import '../plugin_api/cooking_plugin.dart';
import '../plugin_api/plugin_runtime.dart';

/// Session-owned cooking port. Never retains credentials, HTTP ports or live
/// resolver callbacks. Uploads are explicitly ingested by later consumers.
final class CookingUploadLease {
  const CookingUploadLease._(
    this.siteUrl,
    this.accountId,
    this.generation,
    this._host,
  );
  final String siteUrl, accountId;
  final int generation;
  final ApplicationCooking _host;
}

final class ApplicationCooking {
  ApplicationCooking({
    required InstalledPlugins plugins,
    CookingServicePort? service,
  }) : _plugins = List.unmodifiable(plugins.cookingPlugins),
       configuration = cookingConfiguration(plugins.cookingPlugins),
       service = service ?? CookingHostService();

  final List<CookingPlugin> _plugins;
  final CookingConfiguration configuration;
  final CookingServicePort service;
  final Map<String, int> _generations = {};
  final Map<String, String> _accounts = {};
  final Map<String, Map<String, Object?>> _uploads = {};
  final Map<String, CookingCachedMetadata> _metadata = {};
  final _inputLimited = Expando<bool>();
  final _requestRevisions = Expando<int>();
  final Map<String, int> _contextRevisions = {};
  final Map<String, Set<_CookingContextObserver>> _contextObservers = {};
  bool _disposed = false;
  Future<void>? _disposing;

  Future<bool> start() => _disposed ? Future.value(false) : service.start();

  int contextRevisionFor(String siteUrl) => _contextRevisions[siteUrl] ?? 0;

  /// Invalidates prepared work without rebuilding or retaining its snapshot.
  /// Host-owned config and identity caches use the same site-scoped signal.
  void contextChanged(String siteUrl) {
    if (_disposed) return;
    _contextRevisions[siteUrl] = contextRevisionFor(siteUrl) + 1;
    for (final observer
        in _contextObservers[siteUrl]?.toList() ??
            const <_CookingContextObserver>[]) {
      observer.schedule();
    }
  }

  void Function() watchContext(String siteUrl, void Function() onChanged) {
    if (_disposed) return () {};
    final observer = _CookingContextObserver(onChanged);
    (_contextObservers[siteUrl] ??= {}).add(observer);
    return () {
      observer.retire();
      final observers = _contextObservers[siteUrl];
      observers?.remove(observer);
      if (observers?.isEmpty ?? false) _contextObservers.remove(siteUrl);
    };
  }

  bool isCurrent(CookingRequest request) =>
      !_disposed &&
      _requestRevisions[request] ==
          contextRevisionFor(request.snapshot.siteId) &&
      _accounts[request.snapshot.siteId] == request.snapshot.accountId &&
      (_generations[request.snapshot.siteId] ?? 0) ==
          request.snapshot.accountGeneration;

  CookingRequest _track(CookingRequest request) {
    _requestRevisions[request] = contextRevisionFor(request.snapshot.siteId);
    return request;
  }

  CookingUploadLease captureUploads(String siteUrl, String accountId) {
    _ensureAccount(siteUrl, accountId);
    return CookingUploadLease._(
      siteUrl,
      accountId,
      _generations[siteUrl] ?? 0,
      this,
    );
  }

  void _ensureAccount(String siteUrl, String accountId) {
    if (_disposed) throw StateError('Cooking host disposed');
    if (_accounts.containsKey(siteUrl) && _accounts[siteUrl] != accountId) {
      forget(siteUrl);
    }
    _accounts[siteUrl] = accountId;
  }

  bool ingestUploads(CookingUploadLease lease, Map<String, Object?> uploads) {
    if (_disposed ||
        !identical(lease._host, this) ||
        _accounts[lease.siteUrl] != lease.accountId ||
        (_generations[lease.siteUrl] ?? 0) != lease.generation) {
      return false;
    }
    _uploads[lease.siteUrl] = CookingSnapshot(
      siteId: lease.siteUrl,
      accountId: lease.accountId,
      uploads: uploads,
    ).uploads;
    service.invalidate();
    contextChanged(lease.siteUrl);
    return true;
  }

  bool ingestMetadata(
    CookingUploadLease lease,
    CookingCachedMetadata metadata,
  ) {
    if (_disposed ||
        !identical(lease._host, this) ||
        _accounts[lease.siteUrl] != lease.accountId ||
        (_generations[lease.siteUrl] ?? 0) != lease.generation) {
      return false;
    }
    _metadata[lease.siteUrl] = metadata;
    service.invalidate();
    contextChanged(lease.siteUrl);
    return true;
  }

  CookingRequest request({
    required String siteUrl,
    required String accountId,
    required String raw,
    required SiteConfig config,
    CookingProfile profile = CookingProfile.post,
    CookingContext context = const CookingContext(),
    CookingCachedMetadata? cachedMetadata,
    Map<String, Object?> mentions = const {},
    Map<String, Object?> hashtags = const {},
    Map<String, Object?> customEmoji = const {},
    bool staleSettings = false,
  }) {
    _ensureAccount(siteUrl, accountId);
    if (raw.length > 65536) {
      return _track(
        CookingRequest(
          raw: raw,
          profile: profile,
          configuration: configuration,
          snapshot: CookingSnapshot(
            siteId: siteUrl,
            accountId: accountId,
            accountGeneration: _generations[siteUrl] ?? 0,
          ),
        ),
      );
    }
    // Select from already validated caches before constructing the request's
    // snapshot. Merging entire caches first can exceed its aggregate limit.
    final stored = _metadata[siteUrl]?.snapshot;
    final supplied = cachedMetadata?.snapshot;
    final selection = _MetadataSelection(raw);
    Map<String, Object?> merged(
      Map<String, Object?> Function(CookingSnapshot) field,
    ) => {
      ...?stored == null ? null : field(stored),
      ...?supplied == null ? null : field(supplied),
    };
    List<T> list<T>(List<T> Function(CookingSnapshot) field) {
      final incoming = supplied == null ? <T>[] : field(supplied);
      return incoming.isNotEmpty
          ? incoming
          : stored == null
          ? <T>[]
          : field(stored);
    }

    // These fields affect policy or matching, so never silently truncate them.
    final always = <String, Object?>{
      'customEmojiTranslation': merged((s) => s.customEmojiTranslation),
      'unicodeEmoji': merged((s) => s.unicodeEmoji),
      'emojiDenyList': list((s) => s.emojiDenyList),
      'allowedMediaOrigins': list((s) => s.allowedMediaOrigins),
      'hashtagPriorities': merged((s) => s.hashtagPriorities),
      'hashtagIcons': merged((s) => s.hashtagIcons),
      'censoredRegexp': list((s) => s.censoredRegexp),
      'watchedWordsReplace': merged((s) => s.watchedWordsReplace),
      'watchedWordsLink': merged((s) => s.watchedWordsLink),
    };
    if (!selection.reserve(always)) {
      final limited = CookingRequest(
        raw: raw,
        profile: profile,
        configuration: configuration,
        snapshot: CookingSnapshot(
          siteId: siteUrl,
          accountId: accountId,
          accountGeneration: _generations[siteUrl] ?? 0,
        ),
      );
      _inputLimited[limited] = true;
      return _track(limited);
    }
    Map<String, Object?> relevant(
      Map<String, Object?> Function(CookingSnapshot) field, {
      Map<String, Object?> legacy = const {},
      Set<String> references = const {},
    }) => selection.relevant([
      legacy,
      if (stored != null) field(stored),
      if (supplied != null) field(supplied),
    ], references: references);
    final uploads = selection.relevant([_uploads[siteUrl] ?? const {}]);
    final uploadUrls = <String>{
      for (final value in uploads.values)
        if (value is Map && value['url'] is String) value['url'] as String,
    };
    return _track(
      CookingRequest(
        raw: raw,
        profile: profile,
        configuration: configuration,
        snapshot: CookingSnapshot(
          siteId: siteUrl,
          accountId: accountId,
          baseUrl: siteUrl,
          context: context,
          accountGeneration: _generations[siteUrl] ?? 0,
          siteSettings: config.cookingSettings,
          provenance: {
            'knownSettings': config.cookingKnownSettings.toList()..sort(),
            'staleSettings': staleSettings || config.cookingSettingsStale,
          },
          uploads: uploads,
          mentions: relevant((s) => s.mentions, legacy: mentions),
          avatars: relevant((s) => s.avatars),
          primaryGroups: relevant((s) => s.primaryGroups),
          topics: relevant((s) => s.topics),
          oneboxes: relevant((s) => s.oneboxes),
          inlineOneboxes: relevant((s) => s.inlineOneboxes),
          media: relevant((s) => s.media, references: uploadUrls),
          customEmojiTranslation:
              always['customEmojiTranslation']! as Map<String, Object?>,
          unicodeEmoji: always['unicodeEmoji']! as Map<String, Object?>,
          emojiDenyList: always['emojiDenyList']! as List<String>,
          allowedMediaOrigins: always['allowedMediaOrigins']! as List<String>,
          hashtagPriorities:
              always['hashtagPriorities']! as Map<String, Object?>,
          hashtagIcons: always['hashtagIcons']! as Map<String, Object?>,
          censoredRegexp: always['censoredRegexp']! as List<Object?>,
          watchedWordsReplace:
              always['watchedWordsReplace']! as Map<String, Object?>,
          watchedWordsLink: always['watchedWordsLink']! as Map<String, Object?>,
          hashtags: selection.relevant([hashtags]),
          customEmoji: selection.relevant([customEmoji]),
          pluginContext: {
            for (final plugin in _plugins)
              plugin.name: plugin.projectCookingContext(
                CookingPluginData(plugin.name, config.plugins),
              ),
          },
        ),
      ),
    );
  }

  Future<CookingResult> cook(CookingRequest request) {
    if (request.raw.length > 65536) {
      return Future.value(
        readableFallback(request.raw, CookingFailure.inputLimit),
      );
    }
    final snapshot = request.snapshot;
    if (_disposed ||
        _accounts[snapshot.siteId] != snapshot.accountId ||
        (_generations[snapshot.siteId] ?? 0) != snapshot.accountGeneration ||
        jsonEncode(request.effectiveConfiguration.toJson()) !=
            jsonEncode(configuration.toJson())) {
      return Future.value(
        readableFallback(
          request.raw,
          _disposed ? CookingFailure.disposed : CookingFailure.stale,
        ).forRequest(request),
      );
    }
    if (_inputLimited[request] == true) {
      return Future.value(
        readableFallback(
          request.raw,
          CookingFailure.inputLimit,
        ).forRequest(request),
      );
    }
    return service.cook(request);
  }

  void forget(String siteUrl) {
    _generations.update(siteUrl, (value) => value + 1, ifAbsent: () => 1);
    _uploads.remove(siteUrl);
    _metadata.remove(siteUrl);
    _accounts.remove(siteUrl);
    service.invalidate();
    contextChanged(siteUrl);
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    for (final observers in _contextObservers.values) {
      for (final observer in observers) {
        observer.retire();
      }
    }
    _contextObservers.clear();
    _uploads.clear();
    _metadata.clear();
    await service.dispose();
  }
}

final class _CookingContextObserver {
  _CookingContextObserver(this.onChanged);
  final void Function() onChanged;
  bool _active = true;
  bool _pending = false;

  void schedule() {
    if (!_active || _pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      if (_active) onChanged();
    });
  }

  void retire() => _active = false;
}

// UTF-8 JSON bytes also bound string units and node counts. Leave headroom for
// identity, settings, provenance and owner context within the snapshot limit.
final class _MetadataSelection {
  _MetadataSelection(String raw) : _raw = raw.toLowerCase();
  final String _raw;
  var _remaining = 96 * 1024;

  bool reserve(Object value) {
    final cost = utf8.encode(jsonEncode(value)).length;
    if (cost > _remaining) return false;
    _remaining -= cost;
    return true;
  }

  Map<String, Object?> relevant(
    List<Map<String, Object?>> layers, {
    Set<String> references = const {},
  }) {
    final keys = {for (final layer in layers) ...layer.keys}.toList()..sort();
    final selected = <String, Object?>{};
    var bytes = 0;
    for (final key in keys) {
      if (!_raw.contains(key.split('::').first.toLowerCase()) &&
          !references.contains(key)) {
        continue;
      }
      final value = layers.lastWhere((layer) => layer.containsKey(key))[key];
      final cost = utf8.encode(jsonEncode({key: value})).length;
      if (cost > 8192 ||
          bytes + cost > 32768 ||
          cost > _remaining ||
          selected.length >= 128) {
        continue;
      }
      selected[key] = value;
      bytes += cost;
      _remaining -= cost;
    }
    return selected;
  }
}
