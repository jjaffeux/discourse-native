/// Ending one of an account's browser sessions, as the web client's security
/// preferences do.
abstract interface class UserAuthTokensApi {
  /// Signs the session [tokenId] out. Core refuses the session that made the
  /// request, which a request signed with a user API key never is.
  Future<void> revokeAuthToken({
    required String siteUrl,
    required String apiKey,
    required String username,
    required int tokenId,
    String? clientId,
  });
}
