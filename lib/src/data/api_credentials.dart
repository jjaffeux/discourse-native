abstract interface class SiteApiKeyReader {
  Future<String?> apiKeyFor(String siteUrl);
}

abstract interface class ApiCredentialReader implements SiteApiKeyReader {
  Future<String> clientId();
}

/// Answers a site's stored API key only while that site's account is signed
/// in.
///
/// Key presence is not account identity. Secure storage outlives the account
/// boundary: Apple keeps Keychain items when the app is deleted while the
/// instance list goes with it, and a failed local deletion during sign-out or
/// rollback leaves the retired key behind. Either leaves a signed-out forum
/// whose stored key would otherwise read and write as the old account.
///
/// The account is asked again once the read settles, so a sign-out that lands
/// while storage is being read also answers no key.
final class ConnectedAccountCredentials implements ApiCredentialReader {
  const ConnectedAccountCredentials(this._source, {required this.isConnected});

  final ApiCredentialReader _source;
  final bool Function(String siteUrl) isConnected;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (!isConnected(siteUrl)) return null;
    final apiKey = await _source.apiKeyFor(siteUrl);
    return isConnected(siteUrl) ? apiKey : null;
  }

  @override
  Future<String> clientId() => _source.clientId();
}
