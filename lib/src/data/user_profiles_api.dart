import '../models/user_profile.dart';

abstract interface class UserProfilesApi {
  /// A public site answers a reader with no [apiKey].
  Future<UserProfile> userProfile({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  });
}
