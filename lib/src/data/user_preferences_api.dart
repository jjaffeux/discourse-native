import '../models/user_preferences.dart';

abstract interface class UserPreferencesApi {
  Future<UserPreferences> loadUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });

  Future<UserPreferences> updateUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    required UserPreferences fallback,
    required Map<String, Object?> values,
    String? clientId,
  });
}
