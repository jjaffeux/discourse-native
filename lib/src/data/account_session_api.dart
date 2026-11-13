import '../models/discourse_user.dart';

abstract interface class AccountSessionApi {
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });

  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });
}
