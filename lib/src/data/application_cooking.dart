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
  bool _disposed = false;
  Future<void>? _disposing;

  Future<bool> start() => _disposed ? Future.value(false) : service.start();

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
    return true;
  }

  // Bound both entry count and encoded bytes before the worker snapshot budget.
  // Metadata is optional: omitted references remain readable/unresolved.
  Map<String, Object?> _relevant(String raw, Map<String, Object?> values) {
    final selected = <String, Object?>{};
    var bytes = 0;
    for (final key in values.keys.toList()..sort()) {
      if (!raw.toLowerCase().contains(key.split('::').first.toLowerCase())) {
        continue;
      }
      final value = values[key];
      final cost = utf8.encode(jsonEncode({key: value})).length;
      if (cost > 8192 || bytes + cost > 32768 || selected.length >= 128) {
        continue;
      }
      selected[key] = value;
      bytes += cost;
    }
    return selected;
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
      return CookingRequest(
        raw: raw,
        profile: profile,
        configuration: configuration,
        snapshot: CookingSnapshot(
          siteId: siteUrl,
          accountId: accountId,
          accountGeneration: _generations[siteUrl] ?? 0,
        ),
      );
    }
    final stored =
        _metadata[siteUrl]?.snapshot.toJson() ?? const <String, Object?>{};
    final supplied =
        cachedMetadata?.snapshot.toJson() ?? const <String, Object?>{};
    final merged = <String, Object?>{...stored};
    for (final entry in supplied.entries) {
      final value = entry.value;
      if (value is Map) {
        merged[entry.key] = {...?stored[entry.key] as Map?, ...value};
      } else if (value is List && value.isNotEmpty) {
        merged[entry.key] = value;
      }
    }
    final cached = CookingSnapshot.fromJson({
      'siteId': siteUrl,
      'accountId': accountId,
      ...merged,
    });
    return CookingRequest(
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
        uploads: _relevant(raw, _uploads[siteUrl] ?? const {}),
        mentions: _relevant(raw, {...mentions, ...cached.mentions}),
        avatars: _relevant(raw, cached.avatars),
        primaryGroups: _relevant(raw, cached.primaryGroups),
        topics: _relevant(raw, cached.topics),
        oneboxes: _relevant(raw, cached.oneboxes),
        inlineOneboxes: _relevant(raw, cached.inlineOneboxes),
        media: _relevant(raw, cached.media),
        customEmojiTranslation: cached.customEmojiTranslation,
        unicodeEmoji: cached.unicodeEmoji,
        emojiDenyList: cached.emojiDenyList,
        allowedMediaOrigins: cached.allowedMediaOrigins,
        hashtagPriorities: cached.hashtagPriorities,
        hashtagIcons: cached.hashtagIcons,
        censoredRegexp: cached.censoredRegexp,
        watchedWordsReplace: cached.watchedWordsReplace,
        watchedWordsLink: cached.watchedWordsLink,
        hashtags: _relevant(raw, hashtags),
        customEmoji: _relevant(raw, customEmoji),
        pluginContext: {
          for (final plugin in _plugins)
            plugin.name: plugin.projectCookingContext(
              CookingPluginData(plugin.name, config.plugins),
            ),
        },
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
    return service.cook(request);
  }

  void forget(String siteUrl) {
    _generations.update(siteUrl, (value) => value + 1, ifAbsent: () => 1);
    _uploads.remove(siteUrl);
    _metadata.remove(siteUrl);
    _accounts.remove(siteUrl);
    service.invalidate();
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _uploads.clear();
    _metadata.clear();
    await service.dispose();
  }
}
