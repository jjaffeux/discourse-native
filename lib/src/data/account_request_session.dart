import 'dart:async';

import 'api_credentials.dart';
import 'site_lifecycle.dart';

/// Captures identity before private storage is read. A replacement account
/// cannot supply credentials to work started by the retired session.
final class AccountRequestSession {
  const AccountRequestSession(this.siteUrl, this.lease);

  final String siteUrl;
  final SiteLease lease;

  void _requireCurrent() {
    if (!lease.isCurrent) throw const AccountRequestRetiredException();
  }

  Future<AccountRequestCredentials> keyCredentials(
    SiteApiKeyReader reader,
  ) async {
    _requireCurrent();
    final apiKey = await reader.apiKeyFor(siteUrl);
    _requireCurrent();
    return AccountRequestCredentials._(this, apiKey, '');
  }

  AccountRequestCredentials anonymousCredentials() {
    _requireCurrent();
    return AccountRequestCredentials._(this, null, '');
  }

  Future<AccountRequestCredentials> credentials(
    ApiCredentialReader reader,
  ) async {
    _requireCurrent();
    final apiKey = await reader.apiKeyFor(siteUrl);
    _requireCurrent();
    final clientId = apiKey == null ? '' : await reader.clientId();
    _requireCurrent();
    return AccountRequestCredentials._(this, apiKey, clientId);
  }
}

final class AccountRequestCredentials {
  const AccountRequestCredentials._(this._session, this.apiKey, this.clientId);

  final AccountRequestSession _session;
  final String? apiKey;
  final String clientId;

  Future<T> run<T>(Future<T> Function() operation) async {
    _session._requireCurrent();
    final scope = AccountRequestScope._(this);
    final detach = _session.lease.onRetire(scope._retire);
    try {
      return await runZoned(
        operation,
        zoneValues: {AccountRequestScope._key: scope},
      );
    } finally {
      detach();
    }
  }
}

final class AccountRequestScope {
  AccountRequestScope._(this._credentials);

  static final Object _key = Object();
  static AccountRequestScope? get current =>
      Zone.current[_key] as AccountRequestScope?;

  static Future<T> withoutSession<T>(Future<T> Function() operation) =>
      runZoned(operation, zoneValues: {_key: null});

  final AccountRequestCredentials _credentials;
  final Completer<void> _retired = Completer<void>();

  Future<void> get retired => _retired.future;
  Object get session => _credentials._session.lease.session;
  bool get isCurrent => _credentials._session.lease.isCurrent;

  void _retire() {
    if (!_retired.isCompleted) _retired.complete();
  }

  void validateRequest(Uri url, Map<String, String> headers) {
    if (url.origin != Uri.parse(_credentials._session.siteUrl).origin) {
      throw StateError('Request destination does not belong to this session.');
    }
    validateHeaders(headers);
  }

  void validateHeaders(Map<String, String> headers) {
    validate(
      _credentials._session.siteUrl,
      headers['User-Api-Key'],
      headers['User-Api-Client-Id'],
    );
  }

  void validate(String siteUrl, String? apiKey, String? clientId) {
    if (!isCurrent) throw const AccountRequestRetiredException();
    if (siteUrl != _credentials._session.siteUrl ||
        apiKey != _credentials.apiKey ||
        (clientId ?? '') != _credentials.clientId) {
      throw StateError('Request credentials do not belong to this session.');
    }
  }
}

final class AccountRequestRetiredException implements Exception {
  const AccountRequestRetiredException();

  @override
  String toString() => 'Account request session retired.';
}
