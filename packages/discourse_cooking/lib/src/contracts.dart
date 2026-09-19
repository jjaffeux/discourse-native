import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'configuration.dart';
import 'context.dart';
export 'context.dart';
export 'configuration.dart';

/// Selects an explicit cooking feature profile, independent of the renderer.

/// Immutable context captured for one site/account. No live service references.
///
/// The dictionaries preserve upstream metadata shapes. Their JSON values are
/// recursively copied and frozen; later milestones can add richer field types
/// without changing the single serialized request boundary.
final class CookingSnapshot {
  /// Rejects oversized/non-JSON metadata with [ArgumentError] before copying it.
  /// Snapshot producers should select relevant context, not entire site caches.
  factory CookingSnapshot({
    required String siteId,
    required String accountId,
    String baseUrl = '',
    int accountGeneration = 0,
    CookingContext context = const CookingContext(),
    Map<String, Object?> mentions = const {},
    Map<String, Object?> pluginContext = const {},
    Map<String, Object?> provenance = const {},
    Map<String, Object?> siteSettings = const {},
    Map<String, Object?> uploads = const {},
    Map<String, Object?> hashtags = const {},
    Map<String, Object?> customEmoji = const {},
    Map<String, Object?> customEmojiTranslation = const {},
    Map<String, Object?> oneboxes = const {},
    Map<String, Object?> inlineOneboxes = const {},
    Map<String, Object?> topics = const {},
    Map<String, Object?> primaryGroups = const {},
    Map<String, Object?> media = const {},
    Map<String, Object?> hashtagPriorities = const {},
    Map<String, Object?> hashtagIcons = const {},
    Map<String, Object?> watchedWordsReplace = const {},
    Map<String, Object?> watchedWordsLink = const {},
    Map<String, Object?> unicodeEmoji = const {},
    List<String> emojiDenyList = const [],
    List<String> allowedMediaOrigins = const [],
    List<Object?> censoredRegexp = const [],
    Map<String, Object?> avatars = const {},
  }) => CookingSnapshot._(
    _freezeMap({
      'siteId': siteId,
      'accountId': accountId,
      'baseUrl': baseUrl,
      'accountGeneration': accountGeneration,
      'context': context.toJson(),
      'mentions': mentions,
      'pluginContext': pluginContext,
      'provenance': provenance,
      'siteSettings': siteSettings,
      'uploads': uploads,
      'hashtags': hashtags,
      'customEmoji': customEmoji,
      'customEmojiTranslation': customEmojiTranslation,
      'oneboxes': oneboxes,
      'inlineOneboxes': inlineOneboxes,
      'topics': topics,
      'primaryGroups': primaryGroups,
      'media': media,
      'hashtagPriorities': hashtagPriorities,
      'hashtagIcons': hashtagIcons,
      'watchedWordsReplace': watchedWordsReplace,
      'watchedWordsLink': watchedWordsLink,
      'unicodeEmoji': unicodeEmoji,
      'emojiDenyList': emojiDenyList,
      'allowedMediaOrigins': allowedMediaOrigins,
      'censoredRegexp': censoredRegexp,
      'avatars': avatars,
    }, _SnapshotBudget()),
  );

  CookingSnapshot._(Map<String, Object?> json)
    : siteId = json['siteId']! as String,
      accountId = json['accountId']! as String,
      baseUrl = json['baseUrl']! as String,
      accountGeneration = json['accountGeneration']! as int,
      context = CookingContext.fromJson(
        (json['context']! as Map).cast<String, Object?>(),
      ),
      mentions = json['mentions']! as Map<String, Object?>,
      pluginContext = json['pluginContext']! as Map<String, Object?>,
      provenance = json['provenance']! as Map<String, Object?>,
      siteSettings = json['siteSettings']! as Map<String, Object?>,
      uploads = json['uploads']! as Map<String, Object?>,
      hashtags = json['hashtags']! as Map<String, Object?>,
      customEmoji = json['customEmoji']! as Map<String, Object?>,
      customEmojiTranslation =
          json['customEmojiTranslation']! as Map<String, Object?>,
      oneboxes = json['oneboxes']! as Map<String, Object?>,
      inlineOneboxes = json['inlineOneboxes']! as Map<String, Object?>,
      topics = json['topics']! as Map<String, Object?>,
      primaryGroups = json['primaryGroups']! as Map<String, Object?>,
      media = json['media']! as Map<String, Object?>,
      hashtagPriorities = json['hashtagPriorities']! as Map<String, Object?>,
      hashtagIcons = json['hashtagIcons']! as Map<String, Object?>,
      watchedWordsReplace =
          json['watchedWordsReplace']! as Map<String, Object?>,
      watchedWordsLink = json['watchedWordsLink']! as Map<String, Object?>,
      unicodeEmoji = json['unicodeEmoji']! as Map<String, Object?>,
      emojiDenyList = (json['emojiDenyList']! as List).cast<String>(),
      allowedMediaOrigins = (json['allowedMediaOrigins']! as List)
          .cast<String>(),
      censoredRegexp = (json['censoredRegexp']! as List).cast<Object?>(),
      avatars = json['avatars']! as Map<String, Object?>;

  factory CookingSnapshot.fromJson(Map<String, Object?> json) {
    Map<String, Object?> field(String name) =>
        (json[name] as Map?)?.cast<String, Object?>() ?? const {};
    return CookingSnapshot(
      siteId: json['siteId']! as String,
      accountId: json['accountId']! as String,
      baseUrl: json['baseUrl'] as String? ?? '',
      accountGeneration: json['accountGeneration'] as int? ?? 0,
      context: CookingContext.fromJson(field('context')),
      mentions: field('mentions'),
      pluginContext: field('pluginContext'),
      provenance: field('provenance'),
      siteSettings: field('siteSettings'),
      uploads: field('uploads'),
      hashtags: field('hashtags'),
      customEmoji: field('customEmoji'),
      customEmojiTranslation: field('customEmojiTranslation'),
      oneboxes: field('oneboxes'),
      inlineOneboxes: field('inlineOneboxes'),
      topics: field('topics'),
      primaryGroups: field('primaryGroups'),
      media: field('media'),
      hashtagPriorities: field('hashtagPriorities'),
      hashtagIcons: field('hashtagIcons'),
      watchedWordsReplace: field('watchedWordsReplace'),
      watchedWordsLink: field('watchedWordsLink'),
      unicodeEmoji: field('unicodeEmoji'),
      emojiDenyList:
          (json['emojiDenyList'] as List?)?.cast<String>() ?? const [],
      censoredRegexp:
          (json['censoredRegexp'] as List?)?.cast<Object?>() ?? const [],
      allowedMediaOrigins:
          (json['allowedMediaOrigins'] as List?)?.cast<String>() ?? const [],
      avatars: field('avatars'),
    );
  }

  final String siteId;
  final String accountId;
  final String baseUrl;
  final int accountGeneration;
  final CookingContext context;
  final Map<String, Object?> mentions, pluginContext, provenance;
  final Map<String, Object?> siteSettings;
  final Map<String, Object?> uploads;
  final Map<String, Object?> hashtags;
  final Map<String, Object?> customEmoji;
  final Map<String, Object?> customEmojiTranslation;
  final Map<String, Object?> oneboxes;
  final Map<String, Object?> inlineOneboxes;
  final Map<String, Object?> topics;
  final Map<String, Object?> primaryGroups;
  final Map<String, Object?> media;
  final Map<String, Object?> hashtagPriorities;
  final Map<String, Object?> hashtagIcons;
  final Map<String, Object?> watchedWordsReplace;
  final Map<String, Object?> watchedWordsLink;
  final Map<String, Object?> unicodeEmoji;
  final List<String> emojiDenyList;
  final List<String> allowedMediaOrigins;
  final List<Object?> censoredRegexp;
  final Map<String, Object?> avatars;

  Map<String, Object?> toJson() => {
    'siteId': siteId,
    'accountId': accountId,
    'baseUrl': baseUrl,
    'accountGeneration': accountGeneration,
    'context': context.toJson(),
    'mentions': mentions,
    'pluginContext': pluginContext,
    'provenance': provenance,
    'siteSettings': siteSettings,
    'uploads': uploads,
    'hashtags': hashtags,
    'customEmoji': customEmoji,
    'customEmojiTranslation': customEmojiTranslation,
    'oneboxes': oneboxes,
    'inlineOneboxes': inlineOneboxes,
    'topics': topics,
    'primaryGroups': primaryGroups,
    'media': media,
    'hashtagPriorities': hashtagPriorities,
    'hashtagIcons': hashtagIcons,
    'watchedWordsReplace': watchedWordsReplace,
    'watchedWordsLink': watchedWordsLink,
    'unicodeEmoji': unicodeEmoji,
    'emojiDenyList': emojiDenyList,
    'allowedMediaOrigins': allowedMediaOrigins,
    'censoredRegexp': censoredRegexp,
    'avatars': avatars,
  };
}

final class CookingRequest {
  const CookingRequest({
    required this.raw,
    required this.snapshot,
    this.profile = CookingProfile.post,
    this.configuration,
  });

  factory CookingRequest.fromJson(Map<String, Object?> json) => CookingRequest(
    raw: json['raw']! as String,
    snapshot: CookingSnapshot.fromJson(
      (json['snapshot']! as Map).cast<String, Object?>(),
    ),
    profile: CookingProfile.fromJson(json['profile']),
    configuration: json['configuration'] == null
        ? null
        : CookingConfiguration.fromJson(
            (json['configuration']! as Map).cast<String, Object?>(),
          ),
  );

  final String raw;
  final CookingProfile profile;
  final CookingSnapshot snapshot;
  final CookingConfiguration? configuration;
  CookingConfiguration get effectiveConfiguration =>
      configuration ?? CookingConfiguration();
  String get contextFingerprint => cookingFingerprint({
    'snapshot': snapshot.toJson(),
    'profile': profile.toJson(),
    'configuration': effectiveConfiguration.toJson(),
    'engine': cookingEngineRevision,
    'bundle': cookingBundleRevision,
  });
  String get fingerprint =>
      cookingFingerprint({'context': contextFingerprint, 'raw': raw});

  Map<String, Object?> toJson() => {
    'raw': raw,
    'profile': profile.toJson(),
    'configuration': effectiveConfiguration.toJson(),
    'snapshot': snapshot.toJson(),
  };
}

enum CookingFailure {
  inputLimit,
  outputLimit,
  timeout,
  unavailable,
  engine,
  busy,
  disposed,
  stale,
}

/// HTML is always provisional. Normal server responses remain authoritative.
final class CookingResult {
  CookingResult({
    required this.html,
    this.failure,
    List<String> warnings = const [],
    this.elapsedMicroseconds = 0,
    this.memoryUsageBytes = 0,
    this.requestFingerprint,
    this.contextFingerprint,
    this.provisional = true,
    List<CookingDiagnostic> diagnostics = const [],
    List<CookingUnresolvedReference> unresolvedReferences = const [],
  }) : warnings = List.unmodifiable(warnings),
       diagnostics = List.unmodifiable(diagnostics),
       unresolvedReferences = List.unmodifiable(unresolvedReferences);

  factory CookingResult.fromJson(Map<String, Object?> json) => CookingResult(
    html: json['html']! as String,
    requestFingerprint: json['requestFingerprint'] as String?,
    contextFingerprint: json['contextFingerprint'] as String?,
    provisional: json['provisional'] as bool? ?? true,
    diagnostics: (json['diagnostics'] as List? ?? [])
        .map(
          (v) => CookingDiagnostic.fromJson((v as Map).cast<String, Object?>()),
        )
        .toList(),
    unresolvedReferences: (json['unresolvedReferences'] as List? ?? [])
        .map(
          (v) => CookingUnresolvedReference.fromJson(
            (v as Map).cast<String, Object?>(),
          ),
        )
        .toList(),
    failure: json['failure'] == null
        ? null
        : CookingFailure.values.byName(json['failure']! as String),
    warnings: (json['warnings'] as List? ?? const []).cast<String>(),
    elapsedMicroseconds: json['elapsedMicroseconds'] as int? ?? 0,
    memoryUsageBytes: json['memoryUsageBytes'] as int? ?? 0,
  );

  final String html;
  final String? requestFingerprint, contextFingerprint;
  final bool provisional;
  final List<CookingDiagnostic> diagnostics;
  final List<CookingUnresolvedReference> unresolvedReferences;
  CookingResult forRequest(CookingRequest request) => CookingResult(
    html: html,
    failure: failure,
    warnings: warnings,
    elapsedMicroseconds: elapsedMicroseconds,
    memoryUsageBytes: memoryUsageBytes,
    requestFingerprint: request.fingerprint,
    contextFingerprint: request.contextFingerprint,
    provisional: provisional,
    diagnostics: diagnostics,
    unresolvedReferences: unresolvedReferences,
  );
  final CookingFailure? failure;
  final List<String> warnings;
  final int elapsedMicroseconds;
  final int memoryUsageBytes;
  bool get isFallback => failure != null;

  Map<String, Object?> toJson() => {
    'html': html,
    'requestFingerprint': requestFingerprint,
    'contextFingerprint': contextFingerprint,
    'provisional': provisional,
    'diagnostics': diagnostics.map((v) => v.toJson()).toList(),
    'unresolvedReferences': unresolvedReferences
        .map((v) => v.toJson())
        .toList(),
    'failure': failure?.name,
    'warnings': warnings,
    'elapsedMicroseconds': elapsedMicroseconds,
    'memoryUsageBytes': memoryUsageBytes,
  };
}

final class _SnapshotBudget {
  int units = 262144;
  int nodes = 65536;
  void consume(Object? value, int depth) {
    if (depth > 32) throw ArgumentError('Snapshot nesting exceeds 32 levels');
    if (--nodes < 0) throw ArgumentError('Snapshot exceeds 65,536 values');
    if (value is String) units -= value.length;
    if (units < 0) throw ArgumentError('Snapshot exceeds 262,144 string units');
  }
}

Map<String, Object?> _freezeMap(
  Map<String, Object?> value,
  _SnapshotBudget budget, [
  int depth = 0,
]) {
  budget.consume(value, depth);
  if (value.length > budget.nodes ~/ 2) {
    throw ArgumentError('Snapshot exceeds 65,536 values');
  }
  return Map.unmodifiable(
    Map.fromEntries(
      (value.keys.toList()..sort()).map((key) {
        final item = value[key];
        budget.consume(key, depth + 1);
        return MapEntry(key, _freeze(item, budget, depth + 1));
      }),
    ),
  );
}

Object? _freeze(Object? value, _SnapshotBudget budget, int depth) {
  if (value is Map<String, Object?>) return _freezeMap(value, budget, depth);
  budget.consume(value, depth);
  if (value is List<Object?> && value.length > budget.nodes) {
    throw ArgumentError('Snapshot exceeds 65,536 values');
  }
  return switch (value) {
    null || String() || bool() || int() => value,
    double() when value.isFinite => value,
    List<Object?>() => List<Object?>.unmodifiable(
      value.map((item) => _freeze(item, budget, depth + 1)),
    ),
    _ => throw ArgumentError('Snapshot values must be finite JSON values'),
  };
}

/// Bounded escaped text is safe even if the engine never starts.
CookingResult readableFallback(String raw, CookingFailure failure) {
  const limit = 8192;
  final truncated = raw.length > limit;
  var end = truncated ? limit : raw.length;
  if (end > 0 &&
      raw.codeUnitAt(end - 1) >= 0xd800 &&
      raw.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  final text = const HtmlEscape().convert(raw.substring(0, end));
  return CookingResult(
    html: '<pre>$text${truncated ? '\n…' : ''}</pre>',
    failure: failure,
    warnings: ['offline-cooking-${failure.name}'],
    diagnostics: [
      CookingDiagnostic(
        'offline-cooking-${failure.name}',
        severity: CookingDiagnosticSeverity.error,
      ),
    ],
  );
}

String cookingFingerprint(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

enum CookingDiagnosticSeverity { info, warning, error }

final class CookingDiagnostic {
  const CookingDiagnostic(
    this.code, {
    this.severity = CookingDiagnosticSeverity.warning,
  });
  final String code;
  final CookingDiagnosticSeverity severity;
  factory CookingDiagnostic.fromJson(Map<String, Object?> json) =>
      CookingDiagnostic(
        json['code']! as String,
        severity: CookingDiagnosticSeverity.values.byName(
          json['severity']! as String,
        ),
      );
  Map<String, Object?> toJson() => {'code': code, 'severity': severity.name};
}

enum CookingReferenceKind { upload, mention, hashtag, topic, onebox }

final class CookingUnresolvedReference {
  const CookingUnresolvedReference(this.kind, this.key);
  final CookingReferenceKind kind;
  final String key;
  factory CookingUnresolvedReference.fromJson(Map<String, Object?> json) =>
      CookingUnresolvedReference(
        CookingReferenceKind.values.byName(json['kind']! as String),
        json['key']! as String,
      );
  Map<String, Object?> toJson() => {'kind': kind.name, 'key': key};
}
