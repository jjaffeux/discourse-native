import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/pending_post.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/topic.dart';

abstract interface class ComposerPersistenceApi {
  Future<PostCreation> createPost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? replyToPostNumber,
    bool whisper = false,
    String? draftKey,
    String? clientId,
  });

  Future<PostCreation> createTopic({
    required String siteUrl,
    required String apiKey,
    required String title,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? categoryId,
    Iterable<TopicTag> tags = const [],
    String? targetRecipients,
    String draftKey = ComposerDraft.newTopicDraftKey,
    String? clientId,
    Map<String, Object?> extraFields = const {},
  });

  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? originalText,
    String? editReason,
    String? clientId,
  });

  Future<int?> saveDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    required String data,
    String? owner,
    String? clientId,
  });

  /// [forPrivateMessage] marks a new message or a post in one, where the site
  /// may let staff attach any file. An enforced [sizeLimit] refuses a larger
  /// file before any request, and any limit names the ceiling when the site
  /// answers 413.
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    ComposerUploadType uploadType = ComposerUploadType.composer,
    bool forPrivateMessage = false,
    ComposerUploadSizeLimit? sizeLimit,
    String? clientId,
  });

  Future<Map<String, String>> lookupUploadUrls({
    required String siteUrl,
    required String apiKey,
    required Iterable<String> shortUrls,
    String? clientId,
  });

  Future<({ComposerDraft? draft, int sequence})> draft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    String? clientId,
  });

  /// Every post of [username]'s still waiting for review, newest first.
  Future<List<PendingPost>> pendingPosts({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });
}
