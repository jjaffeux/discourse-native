import 'dart:collection';

import '../plugin_api/background_retention.dart';
import '../plugin_api/plugin_manifest.dart';

typedef PluginBackgroundSiteValidator = bool Function(String siteUrl);

/// Shell-owned composition of plugin background-retention leases.
///
/// Plugins receive only [_ScopedPluginBackgroundRetentionHost]. The registry
/// keeps ownership out-of-band, so a hostile capability cannot spoof another
/// module id, enumerate claims, or release a lease it did not acquire.
final class PluginBackgroundRetentionRegistry {
  PluginBackgroundRetentionRegistry({
    required this._canRetain,
    required this._onChanged,
  });

  final PluginBackgroundSiteValidator _canRetain;
  final void Function() _onChanged;
  final Map<Object, ({PluginId owner, String siteUrl})> _claims = {};
  final Map<String, int> _siteClaimCounts = {};
  final Map<PluginId, _ScopedPluginBackgroundRetentionHost> _hosts = {};
  bool _closed = false;

  Set<String> get siteUrls =>
      UnmodifiableSetView(_siteClaimCounts.keys.toSet());

  bool retains(String siteUrl) => _siteClaimCounts.containsKey(siteUrl);

  PluginBackgroundRetentionHost scopedTo(PluginId owner) {
    if (_closed) throw StateError('Background retention is closed.');
    return _hosts.putIfAbsent(
      owner,
      () => _ScopedPluginBackgroundRetentionHost(this, owner),
    );
  }

  PluginBackgroundRetentionLease _retain(PluginId owner, String siteUrl) {
    if (_closed) throw StateError('Background retention is closed.');
    final normalized = siteUrl.trim();
    if (normalized.isEmpty || !_canRetain(normalized)) {
      throw ArgumentError.value(
        siteUrl,
        'siteUrl',
        'Only a configured site can be retained.',
      );
    }

    final token = Object();
    final firstForSite = !_siteClaimCounts.containsKey(normalized);
    _claims[token] = (owner: owner, siteUrl: normalized);
    _siteClaimCounts.update(
      normalized,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    if (firstForSite) _onChanged();
    return _PluginBackgroundRetentionLease(this, token, normalized);
  }

  void _release(Object token) {
    final claim = _claims.remove(token);
    if (claim == null) return;
    final count = _siteClaimCounts[claim.siteUrl]! - 1;
    if (count > 0) {
      _siteClaimCounts[claim.siteUrl] = count;
      return;
    }
    _siteClaimCounts.remove(claim.siteUrl);
    if (!_closed) _onChanged();
  }

  void releaseOwner(PluginId owner) {
    if (_closed) return;
    _hosts.remove(owner)?._revoke();
    final tokens = [
      for (final entry in _claims.entries)
        if (entry.value.owner == owner) entry.key,
    ];
    if (tokens.isEmpty) return;
    final before = _siteClaimCounts.keys.toSet();
    for (final token in tokens) {
      final claim = _claims.remove(token)!;
      final count = _siteClaimCounts[claim.siteUrl]! - 1;
      if (count == 0) {
        _siteClaimCounts.remove(claim.siteUrl);
      } else {
        _siteClaimCounts[claim.siteUrl] = count;
      }
    }
    if (!before.containsAll(_siteClaimCounts.keys) ||
        !Set<String>.of(_siteClaimCounts.keys).containsAll(before)) {
      _onChanged();
    }
  }

  /// Releases every claim for one forgotten site without revoking otherwise
  /// valid owner-scoped hosts.
  void releaseSite(String siteUrl) {
    if (_closed) return;
    final normalized = siteUrl.trim();
    final tokens = [
      for (final entry in _claims.entries)
        if (entry.value.siteUrl == normalized) entry.key,
    ];
    if (tokens.isEmpty) return;
    for (final token in tokens) {
      _claims.remove(token);
    }
    _siteClaimCounts.remove(normalized);
    _onChanged();
  }

  void close() {
    if (_closed) return;
    final changed = _siteClaimCounts.isNotEmpty;
    _closed = true;
    for (final host in _hosts.values) {
      host._revoke();
    }
    _claims.clear();
    _siteClaimCounts.clear();
    _hosts.clear();
    if (changed) _onChanged();
  }
}

final class _ScopedPluginBackgroundRetentionHost
    implements PluginBackgroundRetentionHost {
  _ScopedPluginBackgroundRetentionHost(this._registry, this._owner);

  final PluginBackgroundRetentionRegistry _registry;
  final PluginId _owner;
  bool _revoked = false;

  void _revoke() => _revoked = true;

  @override
  PluginBackgroundRetentionLease retain(String siteUrl) {
    if (_revoked) {
      throw StateError('Background retention authority is revoked.');
    }
    return _registry._retain(_owner, siteUrl);
  }
}

final class _PluginBackgroundRetentionLease
    implements PluginBackgroundRetentionLease {
  _PluginBackgroundRetentionLease(this._registry, this._token, this.siteUrl);

  final PluginBackgroundRetentionRegistry _registry;
  final Object _token;

  @override
  final String siteUrl;

  @override
  bool get isReleased => !_registry._claims.containsKey(_token);

  @override
  void release() => _registry._release(_token);
}
