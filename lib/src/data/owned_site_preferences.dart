part of 'site_preference_keys.dart';

enum SitePreferenceScope { site, account }

final class SitePreferenceIdentity {
  const SitePreferenceIdentity.site(this.siteUrl) : account = null;
  const SitePreferenceIdentity.account(this.siteUrl, String this.account);

  final String siteUrl;
  final String? account;

  SitePreferenceScope get scope =>
      account == null ? SitePreferenceScope.site : SitePreferenceScope.account;
}

/// The native preference type, kept separate from a store's domain decoding.
@PreferenceStorage.adapter(
  'OwnedSitePreferences supplies the identity for native preference values.',
)
final class SitePreferenceValue<T extends Object> {
  const SitePreferenceValue._(this._read, this._write);

  static const string = SitePreferenceValue<String>._(
    _readString,
    _writeString,
  );
  static const stringList = SitePreferenceValue<List<String>>._(
    _readStringList,
    _writeStringList,
  );

  final T? Function(SharedPreferences, String) _read;
  final Future<bool> Function(SharedPreferences, String, T) _write;

  static String? _readString(SharedPreferences preferences, String key) =>
      preferences.getString(key);
  static Future<bool> _writeString(
    SharedPreferences preferences,
    String key,
    String value,
  ) => preferences.setString(key, value);
  static List<String>? _readStringList(
    SharedPreferences preferences,
    String key,
  ) => preferences.getStringList(key);
  static Future<bool> _writeStringList(
    SharedPreferences preferences,
    String key,
    List<String> value,
  ) => preferences.setStringList(key, value);
}

/// Owns exact identities, compatible legacy reads, and removal ordering.
/// Account spelling remains the domain store's existing policy.
@PreferenceStorage.adapter(
  'Typed site preferences serialize migration and permanent removal by exact site identity.',
)
final class OwnedSitePreferences<T extends Object> {
  const OwnedSitePreferences({
    required this.id,
    required this.scope,
    required this.value,
    this.legacy,
  });

  final String id;
  final SitePreferenceScope scope;
  final SitePreferenceValue<T> value;

  final SitePreferenceKey? legacy;

  String keyFor(SitePreferenceIdentity identity) {
    if (identity.scope != scope) {
      throw ArgumentError('Preference identity has the wrong scope.');
    }
    return _encodeOwnedPreference(id, identity);
  }

  String? _legacyKey(SitePreferenceIdentity identity) {
    final key = legacy;
    if (key == null) return null;
    final account = identity.account;
    return account == null
        ? key.of(identity.siteUrl)
        : '${key.of(identity.siteUrl)}.${Uri.encodeComponent(account)}';
  }

  Future<T?> read(SitePreferenceIdentity identity) {
    final key = keyFor(identity);
    final owner = _preferenceOwner(identity.siteUrl);
    return _ownedPreferenceOperations.run(
      owner: _ownedPreferenceOwners,
      key: identity.siteUrl,
      operation: () async {
        if (!_ownsPreference(identity.siteUrl, owner)) return null;
        try {
          final preferences = await SharedPreferences.getInstance();
          if (!_ownsPreference(identity.siteUrl, owner)) return null;
          final rejected = _rejectedPreferenceValues[preferences];
          if (rejected?.containsKey(key) == true) {
            final previous = rejected![key];
            if (previous != null) return previous as T;
          } else if (preferences.containsKey(key)) {
            return value._read(preferences, key);
          }
          final oldKey = _legacyKey(identity);
          if (oldKey == null) return null;
          final oldValue = value._read(preferences, oldKey);
          if (oldValue == null) return null;
          // Old dotted keys can have another owner. Copy without deleting them.
          try {
            await _save(preferences, key, oldValue);
          } catch (_) {}
          return _ownsPreference(identity.siteUrl, owner) ? oldValue : null;
        } catch (error) {
          return null;
        }
      },
    );
  }

  Future<void> write(SitePreferenceIdentity identity, T newValue) {
    final key = keyFor(identity);
    final owner = _preferenceOwner(identity.siteUrl);
    return _ownedPreferenceOperations.run<void>(
      owner: _ownedPreferenceOwners,
      key: identity.siteUrl,
      operation: () async {
        if (!_ownsPreference(identity.siteUrl, owner)) return;
        try {
          final preferences = await SharedPreferences.getInstance();
          if (!_ownsPreference(identity.siteUrl, owner)) return;
          await _save(preferences, key, newValue);
        } catch (_) {}
      },
    );
  }

  Future<void> _save(SharedPreferences preferences, String key, T data) async {
    final rejected = _rejectedPreferenceValues[preferences] ??= {};
    final previous = rejected.containsKey(key)
        ? rejected[key]
        : preferences.get(key);
    try {
      if (!await value._write(preferences, key, data)) {
        throw StateError('Could not persist site preferences.');
      }
      rejected.remove(key);
      _failedPreferenceRemovals[preferences]?.remove(key);
    } catch (_) {
      // The backend may reject a value already present in the shared cache.
      // Preserve this key's last accepted value without reloading other sites.
      rejected[key] = previous;
      rethrow;
    }
  }
}

const _ownedPreferencePrefix = 'discourse_native.site.v1.';
final _ownedPreferenceOperations = SerialOperationQueue();
final _ownedPreferenceOwners = <String, Object>{};
final _rejectedPreferenceValues = Expando<Map<String, Object?>>();
final _failedPreferenceRemovals = Expando<Set<String>>();

Object _preferenceOwner(String site) =>
    _ownedPreferenceOwners.putIfAbsent(site, Object.new);
bool _ownsPreference(String site, Object owner) =>
    identical(_ownedPreferenceOwners[site], owner);

String _encodeOwnedPreference(String id, SitePreferenceIdentity identity) =>
    '$_ownedPreferencePrefix${base64Url.encode(utf8.encode(jsonEncode([id, identity.scope.name, identity.siteUrl, identity.account]))).replaceAll('=', '')}';

SitePreferenceIdentity? _ownedPreferenceIdentity(String key) {
  if (!key.startsWith(_ownedPreferencePrefix)) return null;
  try {
    final encoded = key.substring(_ownedPreferencePrefix.length);
    final tuple = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
    );
    if (tuple is! List || tuple.length != 4) return null;
    if (tuple case [String id, 'site', String site, null]) {
      final identity = SitePreferenceIdentity.site(site);
      return _encodeOwnedPreference(id, identity) == key ? identity : null;
    }
    if (tuple case [String id, 'account', String site, String account]) {
      final identity = SitePreferenceIdentity.account(site, account);
      return _encodeOwnedPreference(id, identity) == key ? identity : null;
    }
  } on FormatException {
    return null;
  }
  return null;
}

@PreferenceStorage.adapter(
  'Retirement scans exact identities and invalidates admitted site generations.',
)
List<Future<List<bool>>> _retireOwnedPreferences(
  SharedPreferences preferences,
  ForgottenSites sites,
) {
  final knownSites = {
    ..._ownedPreferenceOwners.keys,
    for (final key in {
      ...preferences.getKeys(),
      ...?_failedPreferenceRemovals[preferences],
    })
      if (_ownedPreferenceIdentity(key) case final identity?) identity.siteUrl,
  };
  return [
    for (final site in knownSites)
      if (sites.includes(site)) _enqueueRetiredSiteDeletion(preferences, site),
  ];
}

@PreferenceStorage.adapter(
  'The site mutation queue orders backend completion before deletion and successor writes.',
)
Future<List<bool>> _enqueueRetiredSiteDeletion(
  SharedPreferences preferences,
  String site,
) {
  _ownedPreferenceOwners.remove(site);
  return _ownedPreferenceOperations.run(
    owner: _ownedPreferenceOwners,
    key: site,
    operation: () async {
      final keys = {
        ...preferences.getKeys(),
        ...?_failedPreferenceRemovals[preferences],
      }.where((key) => _ownedPreferenceIdentity(key)?.siteUrl == site);
      final failed = _failedPreferenceRemovals[preferences] ??= {};
      return Future.wait([
        for (final key in keys)
          () async {
            try {
              final saved = await preferences.remove(key);
              if (saved) {
                failed.remove(key);
                _rejectedPreferenceValues[preferences]?.remove(key);
              } else {
                failed.add(key);
              }
              return saved;
            } catch (_) {
              failed.add(key);
              rethrow;
            }
          }(),
      ]);
    },
  );
}
