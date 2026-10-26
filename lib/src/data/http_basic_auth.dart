import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/l10n/strings.dart';

import 'discourse_api_contracts.dart';
import 'http_transport.dart';
import 'private_storage.dart';

final class HttpBasicAuthentication {
  HttpBasicAuthentication({
    required Uri origin,
    required this.username,
    required this.password,
  }) : origin = Uri.parse(requireSafeHttpUrl(origin).origin) {
    if (username.contains(':') ||
        _controls.hasMatch(username) ||
        _controls.hasMatch(password)) {
      throw const FormatException(
        'Invalid HTTP Basic authentication credentials.',
      );
    }
  }

  static final _controls = RegExp(r'[\x00-\x1f\x7f]');
  final Uri origin;
  final String username;
  final String password;

  String? authorizationFor(Uri destination) =>
      destination.hasAuthority && destination.origin == origin.origin
      ? 'Basic ${base64Encode(utf8.encode('$username:$password'))}'
      : null;

  @override
  String toString() => 'HttpBasicAuthentication(${origin.origin})';
}

final class HttpBasicAuthenticationRequired extends SiteLookupException {
  HttpBasicAuthenticationRequired(Uri url)
    : origin = Uri.parse(requireSafeHttpUrl(url).origin),
      super(SiteLookupFailure.unreachable, url.origin, statusCode: 401);

  final Uri origin;

  @override
  String get message => appL10n.httpBasicAuthenticationRequired(origin.origin);
}

bool hasHttpBasicChallenge(int statusCode, Map<String, String> headers) {
  if (statusCode != 401) return false;
  final value = headers['www-authenticate'];
  if (value == null) return false;
  var quoted = false;
  var escaped = false;
  var start = 0;
  for (var index = 0; index <= value.length; index++) {
    if (index == value.length || (!quoted && value[index] == ',')) {
      if (RegExp(
        r'^\s*Basic(?:\s|$)',
        caseSensitive: false,
      ).hasMatch(value.substring(start, index))) {
        return true;
      }
      start = index + 1;
    } else if (escaped) {
      escaped = false;
    } else if (quoted && value[index] == r'\') {
      escaped = true;
    } else if (value[index] == '"') {
      quoted = !quoted;
    }
  }
  return false;
}

/// Confirmed server credentials are independent of a Discourse account.
/// Loading is explicit so transport construction never reads platform storage.
final class HttpBasicAuthStore {
  HttpBasicAuthStore({PrivateStorage? storage})
    : _storage = storage ?? platformCredentialStorage;

  static final instance = HttpBasicAuthStore();
  static const storageKey = 'http_basic_auth_v1';
  final PrivateStorage _storage;
  Map<String, HttpBasicAuthentication> _credentials = {};
  final Map<String, Object> _versions = {};
  Future<void>? _loading;
  Future<void> _tail = Future.value();
  bool _loaded = false;
  Object _generation = Object();

  Object get generation => _generation;
  String? authorizationFor(Uri url) =>
      _credentials[url.origin]?.authorizationFor(url);
  Object? identityFor(Uri url) => _versions[url.origin];
  bool protects(Uri url) => authorizationFor(url) != null;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final raw = await _storage.read(storageKey);
    final loaded = <String, HttpBasicAuthentication>{};
    if (raw != null) {
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        throw const FormatException('Invalid stored server authentication.');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid stored server authentication.');
      }
      for (final entry in decoded.entries) {
        try {
          final value = entry.value as Map<String, dynamic>;
          final credential = HttpBasicAuthentication(
            origin: Uri.parse(entry.key),
            username: value['username'] as String,
            password: value['password'] as String,
          );
          if (credential.origin.origin != entry.key) continue;
          loaded[entry.key] = credential;
        } catch (_) {}
      }
    }
    _credentials = loaded;
    for (final origin in loaded.keys) {
      _versions[origin] = Object();
    }
    _generation = Object();
    _loaded = true;
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<HttpBasicAuthChange> remember(HttpBasicAuthentication credential) =>
      _mutate(() async {
        await load();
        final origin = credential.origin.origin;
        final previous = _credentials[origin];
        await _write({..._credentials, origin: credential});
        final version = _versions[origin] = Object();
        return HttpBasicAuthChange._(this, origin, previous, version);
      });

  Future<void> forgetOrigin(Uri origin, {bool Function()? whenUnused}) =>
      _mutate(() async {
        await load();
        if (!_credentials.containsKey(origin.origin) ||
            whenUnused?.call() == false) {
          return;
        }
        await _write(
          {..._credentials}..remove(origin.origin),
          accept: whenUnused,
        );
      });

  Future<void> retainOrigins(Iterable<String> siteUrls) => _mutate(() async {
    await load();
    final origins = {for (final url in siteUrls) Uri.parse(url).origin};
    final retained = {
      for (final entry in _credentials.entries)
        if (origins.contains(entry.key)) entry.key: entry.value,
    };
    if (retained.length != _credentials.length) await _write(retained);
  });

  Future<void> _rollback(HttpBasicAuthChange change) => _mutate(() async {
    if (!identical(_versions[change._origin], change._version)) return;
    final restored = {..._credentials}..remove(change._origin);
    if (change._previous case final previous?) {
      restored[change._origin] = previous;
    }
    await _write(restored);
  });

  Future<void> _write(
    Map<String, HttpBasicAuthentication> credentials, {
    bool Function()? accept,
  }) async {
    String encode(Map<String, HttpBasicAuthentication> values) => jsonEncode({
      for (final entry in values.entries)
        entry.key: {
          'username': entry.value.username,
          'password': entry.value.password,
        },
    });
    await _storage.write(storageKey, encode(credentials));
    if (accept?.call() == false) {
      await _storage.write(storageKey, encode(_credentials));
      return;
    }
    final changed = {..._credentials.keys, ...credentials.keys};
    for (final origin in changed) {
      if (!identical(_credentials[origin], credentials[origin])) {
        if (credentials.containsKey(origin)) {
          _versions[origin] = Object();
        } else {
          _versions.remove(origin);
        }
      }
    }
    _credentials = credentials;
    _generation = Object();
  }
}

final class HttpBasicAuthChange {
  HttpBasicAuthChange._(
    this._store,
    this._origin,
    this._previous,
    this._version,
  );
  final HttpBasicAuthStore _store;
  final String _origin;
  final HttpBasicAuthentication? _previous;
  final Object _version;

  Future<void> rollback() => _store._rollback(this);
}
