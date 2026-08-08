abstract interface class SiteApiKeyReader {
  Future<String?> apiKeyFor(String siteUrl);
}

abstract interface class ApiCredentialReader implements SiteApiKeyReader {
  Future<String> clientId();
}
