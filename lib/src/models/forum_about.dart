import 'json.dart';

/// The public About serializer's identity and optional, permission-gated stats.
final class ForumAbout {
  const ForumAbout({
    required this.title,
    this.description,
    this.extendedDescription,
    this.creationDate,
    this.stats = const {},
  });

  factory ForumAbout.fromJson(Map<String, dynamic> response) {
    final about = jsonObjectFields(response['about']);
    if (about == null) throw const FormatException('Missing About object.');
    final source = about['can_see_about_stats'] == false
        ? null
        : jsonObjectFields(about['stats']);
    return ForumAbout(
      title: jsonString(about['title']),
      description: jsonText(about['description']),
      extendedDescription: jsonHtmlText(about['extended_site_description']),
      creationDate: jsonDate(about['site_creation_date']),
      stats: _stats(source),
    );
  }

  final String title;
  final String? description;
  final String? extendedDescription;
  final DateTime? creationDate;
  final Map<String, int> stats;

  int? get members => stats['users_count'] ?? stats['user_count'];

  /// The API omits this field when Voice or analytics are disabled. The web
  /// initializer additionally requires Voice to be enabled and a nonzero count.
  int? voiceParticipants({required bool voiceEnabled}) {
    final count = stats['voice_users_7_days'];
    return voiceEnabled && count != null && count > 0 ? count : null;
  }

  static Map<String, int> _stats(Map<String, Object?>? source) {
    final stats = <String, int>{};
    for (final entry in (source ?? const <String, Object?>{}).entries) {
      final count = _count(entry.value);
      if (count != null) stats[entry.key] = count;
    }
    return Map.unmodifiable(stats);
  }

  static int? _count(Object? value) => switch (value) {
    final int count when count >= 0 => count,
    _ => null,
  };
}
