import '../models/composer_upload.dart';

/// Changing a person's picture, as the web client's avatar selector does:
/// an image is stored as an upload first, then picked by its id.
abstract interface class UserAvatarApi {
  /// Stores [file] as an avatar and answers its upload id.
  ///
  /// Throws a [ComposerUploadException] carrying the site's own refusal.
  Future<int> uploadAvatar({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required Future<void> abortTrigger,
    String? clientId,
  });

  /// Makes the upload [uploadId] this person's picture. A null [uploadId]
  /// returns them to the letter avatar the site draws.
  Future<void> pickAvatar({
    required String siteUrl,
    required String apiKey,
    required String username,
    required int? uploadId,
    String? clientId,
  });
}
