/// Asking the site to change an account's address, as the web client's email
/// preference does.
abstract interface class UserEmailApi {
  /// Requests that [username]'s primary address become [email].
  ///
  /// Nothing changes yet: core mails a confirmation link and keeps the old
  /// address until it is followed. Core answers the same way whether or not
  /// the address is free on a site that hides which addresses are taken.
  Future<void> requestEmailChange({
    required String siteUrl,
    required String apiKey,
    required String username,
    required String email,
    String? clientId,
  });
}
