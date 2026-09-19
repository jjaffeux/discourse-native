/// Explicit, immutable facts for one cook. Defaults are deterministic and do
/// not consult a device clock, timezone, account service, or composer callback.
final class CookingContext {
  const CookingContext({
    this.authorId,
    this.editorId,
    this.topicId,
    this.postId,
    this.authorUsername = '',
    this.locale = 'en',
    this.timezone = 'Etc/UTC',
    this.asOfEpochMilliseconds = 0,
    this.sourcePolicy = CookingSourcePolicy.raw,
  });

  final int? authorId, editorId, topicId, postId;
  final String authorUsername, locale, timezone;
  final int asOfEpochMilliseconds;
  final CookingSourcePolicy sourcePolicy;

  Map<String, Object?> toJson() => {
    'authorId': authorId,
    'editorId': editorId,
    'topicId': topicId,
    'postId': postId,
    'authorUsername': authorUsername,
    'locale': locale,
    'timezone': timezone,
    'asOfEpochMilliseconds': asOfEpochMilliseconds,
    'sourcePolicy': sourcePolicy.name,
  };

  factory CookingContext.fromJson(Map<String, Object?> json) => CookingContext(
    authorId: json['authorId'] as int?,
    editorId: json['editorId'] as int?,
    topicId: json['topicId'] as int?,
    postId: json['postId'] as int?,
    authorUsername: json['authorUsername'] as String? ?? '',
    locale: json['locale'] as String? ?? 'en',
    timezone: json['timezone'] as String? ?? 'Etc/UTC',
    asOfEpochMilliseconds: json['asOfEpochMilliseconds'] as int? ?? 0,
    sourcePolicy: CookingSourcePolicy.values.byName(
      json['sourcePolicy'] as String? ?? 'raw',
    ),
  );
}

enum CookingSourcePolicy { raw, submission }
