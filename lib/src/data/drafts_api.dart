import '../models/user_draft.dart';

abstract interface class DraftsApi {
  Future<UserDraftPage> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  });

  Future<void> deleteUserDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    String? clientId,
  });
}
