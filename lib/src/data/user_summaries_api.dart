import '../models/user_summary.dart';

abstract interface class UserSummariesApi {
  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });
}
